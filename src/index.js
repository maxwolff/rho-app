import 'regenerator-runtime/runtime'
import {ethers} from 'ethers';
import '../build-css/main.css';
import { Elm } from './Main.elm';

const BLOCKS_PER_YEAR = 2102400;
const duration = (10 / BLOCKS_PER_YEAR * 365).toFixed(4);

const app = Elm.Main.init({
  node: document.getElementById('root'),
  flags: {
  	duration: duration,
  	underlying: "DAI",
  	collateral: "cDAI"
  }
});

const MAX_UINT = "57896044618658097711785492504343953926634992332820282019728792003956564819968";

const netMap = {
	"0xNaN": {"name": "development", "host": "http://localhost:8545"},
	// "0x1": {"name": "mainnet", "host": "https://mainnet-eth.compound.finance"},
	"0x2a": {"name": "kovan", "host": "https://kovan-eth.compound.finance"}
}

if (window.ethereum) {
	window.ethereum.on('chainChanged', (chainId) => {
	  window.location.reload();
	});

	window.ethereum.on('accountsChanged', async(accounts) => {
		window.location.reload();
		await subWeb3()
	});
} else {
	app.ports.connectReceiver.send(["none", ""]);
}


const getConfig = (networkName) => {
	return require(`../public/networks/${networkName}.json`);
}

const useMetamask = async (callback) => {
	if (window.ethereum) {
		window.ethereum.autoRefreshOnNetworkChange = false;
		const config = netMap[window.ethereum.chainId];
		if (config != undefined) {
			await callback(config, ethereum);
		} else {
			app.ports.connectReceiver.send(["invalid", ""]);
		}
	}
}

const subWeb3 = async () => {
	return useMetamask((config, ethereum) => {
		if (ethereum.selectedAddress == undefined) {
			app.ports.connectReceiver.send(["unconnected", ""]);
		} else {
			app.ports.connectReceiver.send([config.name, ethereum.selectedAddress]);
			makeWeb3Ports(config, ethereum);
		}
	});
}

app.ports.isConnected.subscribe(async () => {
	await subWeb3();
});

app.ports.connect.subscribe(async () => {
	await useMetamask(async (config, ethereum) => {
		await ethereum.request({method: 'eth_requestAccounts'});
		makeWeb3Ports(config, ethereum);
		app.ports.connectReceiver.send([config.name, ethereum.selectedAddress]);
	});
});

const bn = str => {
	return ethers.BigNumber.from(str);
};

const DAI_DEC = bn(10).pow(18);
const CTOKEN_DEC = bn(10).pow(8);

// fixed num
const fn = bnOrStr => {
	return ethers.FixedNumber.from(bnOrStr);
}

// bn | str => fn
const toAmt = wei => {
	return fn(wei).divUnsafe(fn(DAI_DEC));
}

// bn | str => fn
const toCTokenAmt = cTokenWei => {
	return fn(cTokenWei).divUnsafe(fn(CTOKEN_DEC));
}

const toCTokenWeiStr = cTokenAmt => {
	return fn(cTokenAmt).mulUnsafe(fn(CTOKEN_DEC)).toString().split('.')[0];
};

const toWeiStr = amt => {
	return fn(amt).mulUnsafe(fn(DAI_DEC)).toString().split('.')[0];
}

const toPercFromBlockMantissa = wei => {
	return  toAmt(wei.mul(BLOCKS_PER_YEAR).mul(100)).round(3).toString();
}


const makeWeb3Ports = async ({name, host}, ethereum) => {
	const {rhoLens: rhoLensAddr, cToken: cTokenAddr, rho: rhoAddr} = getConfig(name);

	const i = new ethers.utils.Interface([
		// erc20
		"function allowance(address, address) returns (uint)",
		"function approve(address, uint256)",
		"function balanceOf(address) returns (uint)",

		//rhoLens
		"function toCTokens(uint underlyingAmount) returns (uint cTokenAmount)",
		"function toUnderlying(uint cTokenAmt) returns (uint underlyingAmount)",
		"function getHypotheticalOrderInfo(bool userPayingFixed, uint notionalAmount) returns (uint swapFixedRateMantissa, uint userCollateralCTokens)",

		// rho
		"function supply(uint cTokenSupplyAmount)",
		"function openPayFixedSwap(uint notionalAmount, uint maximumFixedRateMantissa) returns (bytes32 swapHash)",
		"function openReceiveFixedSwap(uint notionalAmount, uint minFixedRateMantissa) returns (bytes32 swapHash)",
		"function supplyAccounts(address) returns (uint amount, uint lastBlock, uint index)"
	]);

	const eventAbi = [
		"event OpenSwap(bytes32 indexed swapHash, bool userPayingFixed, uint benchmarkIndexInit, uint initBlock, uint swapFixedRateMantissa, uint notionalAmount, uint userCollateralCTokens, address indexed owner)",
		"event CloseSwap(bytes32 indexed swapHash, address indexed owner, uint userPayout, uint benchmarkIndexInit, uint benchmarkIndexStored)",
	];

	const send = async (sig, args, to) => {
		const data = i.encodeFunctionData(sig, args);
		return ethereum.request({
			method: 'eth_sendTransaction',
			params: [{to, data, from: ethereum.selectedAddress}]
		});
	};

	const call = async (sig, args, to) => {
		const data = i.encodeFunctionData(sig, args);
		const res = await ethereum.request({
			method: 'eth_call',
			params: [{to, data}]
		});
		return i.decodeFunctionResult(sig, res);
	};

	// PORT fns receive values as strings with decimals. ie "1.5" instead of 1.5e18, so we need to scale up before sending

	app.ports.approveSend.subscribe(async () => {
		await send("approve", [rhoAddr, MAX_UINT], cTokenAddr);
		app.ports.enableReceiver.send(true);
	});

	app.ports.isApprovedCall.subscribe(async () => {
 		if (ethereum.selectedAddress) {
	 		const [allowance] = await call("allowance", [ethereum.selectedAddress, rhoAddr], cTokenAddr);
	 		app.ports.enableReceiver.send(!bn(allowance).isZero());
 		}
	});

	app.ports.supplyToCTokensCall.subscribe(async (underlyingAmt) => {
		const underlyingWei = toWeiStr(underlyingAmt);
		const [cTokens] = await call("toCTokens", [underlyingWei], rhoLensAddr);
		console.log(cTokens.toString(), toCTokenAmt(cTokens).round(2).toString());
		app.ports.supplyToCTokensReceiver.send(toCTokenAmt(cTokens).round(2).toString());
	});

	app.ports.supplyCTokensSend.subscribe(async (supplyAmt) => {
		await send("supply", [toCTokenWeiStr(supplyAmt)], rhoAddr);
	});

	app.ports.orderInfoCall.subscribe(async ([userPayingFixed, notionalAmount]) => {
		const notionalWei = toWeiStr(notionalAmount)
		const [swapRateWei, ctokens] = await call("getHypotheticalOrderInfo", [userPayingFixed, notionalWei], rhoLensAddr);
		const swapRateFixed = toPercFromBlockMantissa(swapRateWei);
		const [underlyingWei] = await call("toUnderlying", [ctokens], rhoLensAddr);
		const underlyingAmt = toAmt(underlyingWei).round(2).toString();
		const cTokenAmt = toCTokenAmt(ctokens).round(2).toString();
		app.ports.orderInfoReceiver.send([swapRateFixed, cTokenAmt, underlyingAmt]);
	});

	app.ports.openSwapSend.subscribe(async ([userPayingFixed, notionalAmount]) => {
		const notionalWei = toWeiStr(notionalAmount);
		const [swapRateWei, _ctokens] = await call("getHypotheticalOrderInfo", [userPayingFixed, notionalWei], rhoLensAddr);
		if (userPayingFixed) {
			const rateBound = swapRateWei.mul(11).div(10);
			await send("openPayFixedSwap", [notionalWei, rateBound], rhoAddr);
		} else {
			const rateBound = swapRateWei.mul(9).div(10);
			await send("openReceiveFixedSwap", [notionalWei, rateBound], rhoAddr);
		}
	});

	app.ports.supplyBalance.subscribe(async () => {
		const {amount: supplyCTokens} = await call("supplyAccounts", [ethereum.selectedAddress], rhoAddr);
		const supplyCTokenAmt = toCTokenAmt(supplyCTokens).round(3).toString();

		const [userCTokenBal] = await call("balanceOf", [ethereum.selectedAddress], cTokenAddr);
		const userCTokenAmt = toCTokenAmt(userCTokenBal).round(3).toString();

		app.ports.userBalancesReceiver.send([supplyCTokenAmt, userCTokenAmt]);
	});

	app.ports.swapHistory.subscribe(async () => {
		const provider = new ethers.providers.Web3Provider(ethereum);
		const rho = new ethers.Contract(rhoAddr, eventAbi, provider);

		const openFilter = rho.filters.OpenSwap(...Array(7).concat(ethereum.selectedAddress));// add some blanks for non indexed params
		const openEvents = await rho.queryFilter(openFilter);

		const closeFilter = rho.filters.CloseSwap(null, ethereum.selectedAddress);
		const closeEvents = await rho.queryFilter(closeFilter);

		const getTimestampFromBlock = async (bn) => {
			return bn.toString()
			// console.log(bn)
			// return (await provider.getBlock(bn.toString()).timestamp);
		}

		const res = openEvents.concat(closeEvents).reduce((acc, cur) => {
			const { args, event } = cur;
			if (event == "OpenSwap") {
				acc[args.swapHash] = {
					initTimestamp: args.initBlock.toString(),
					notional: toAmt(args.notionalAmount).toString(),
					rate: toPercFromBlockMantissa(args.swapFixedRateMantissa),
					userPayingFixed: args.userPayingFixed,
					userPayout: null
				};
			} else {
				acc[args.swapHash] = {
					...acc[args.swapHash],
					userPayout: toAmt(args.userPayout).round(4).toString(),
				};
			}
			return acc;
		}, {});
		console.log(Object.values(res));

		app.ports.swapHistoryReceiver.send(Object.values(res));
	});
}
