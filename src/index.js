import './main.css';
import {ethers} from 'ethers';
import { Elm } from './Main.elm';
import abis from '../public/abis.json';
const BigNumber = require('bignumber.js');


const PRECISION = 5;
const BLOCKS_PER_YEAR = 2102400;
const MAX_UINT = "57896044618658097711785492504343953926634992332820282019728792003956564819968";
const app = Elm.Main.init({
  node: document.getElementById('root')
});

const netMap = {
	"0xNaN": {"name": "development", "host": "http://localhost:8545"},
	"0x1": {"name": "mainnet", "host": "https://mainnet-eth.compound.finance"},
	"0x2a": {"name": "kovan", "host": "https://kovan-eth.compound.finance"}
}


const bn = num => {
	return new BigNumber(num);
};


const DAI_DEC = bn(10).pow(18);
const CTOKEN_DEC = bn(10).pow(8);

//reload page on chainChanged
window.ethereum.on('chainChanged', (chainId) => {
  window.location.reload();
});

window.ethereum.on('accountsChanged', (accounts) => {
	connect();
})

// wei: ethers bn
const fromWei = wei => {
	return bn(wei.toString()).div(DAI_DEC);
}

// cTokenWei: ethers bn
const fromCTokenWei = cTokenWei => {
	return bn(cTokenWei.toString()).div(CTOKEN_DEC);
}

// cTokenAmt: ethers bn
// TODO: this overflows if too big, ethers bn sucks
const toCTokenWei = cTokenAmt => {
	return bn(cTokenAmt.toString()).times(CTOKEN_DEC).toFixed(0);
};

const toWei = (amtStr) => {
	return bn(amtStr).times(DAI_DEC).toFixed(0);
}

const getConfig = (networkName) => {
	return require('../public/networks/' + networkName + '.json');
}

app.ports.connect.subscribe(async () => {await connect()});

const connect = async () => {
	const eth = window.ethereum;
	const config = netMap[eth.chainId];
	if (eth && config != undefined) {
		await eth.request({method: 'eth_requestAccounts'});
		subWeb3(config, eth);
		app.ports.connectReceiver.send({network: config.name, selectedAddr: eth.selectedAddress});
	} else {
		console.log("invalid network");
		app.ports.connectReceiver.send({network: "", selectedAddr: ""});
	}
};

const subWeb3 = async ({name, host}, ethereum) => {
	const {rhoLens: rhoLensAddr, cToken: cTokenAddr, rho: rhoAddr} = getConfig(name);


	// must be to fixed
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

	const i = new ethers.utils.Interface([
		// erc20
		"function allowance(address, address) returns (uint)",
		"function approve(address, uint256)",

		//rhoLens
		"function toCTokens(uint underlyingAmount) returns (uint cTokenAmount)",
		"function toUnderlying(uint cTokenAmt) returns (uint underlyingAmount)",
		"function getHypotheticalOrderInfo(bool userPayingFixed, uint notionalAmount) returns (uint swapFixedRateMantissa, uint userCollateralCTokens)",

		// rho
		"function supply(uint cTokenSupplyAmount)",
		"function openPayFixedSwap(uint notionalAmount, uint maximumFixedRateMantissa) returns (bytes32 swapHash)",
		"function openReceiveFixedSwap(uint notionalAmount, uint minFixedRateMantissa) returns (bytes32 swapHash)"
	]);

	// PORT fns receive values as strings with decimals. ie "1.5" instead of 1.5e18, so we need to scale up before sending

	app.ports.approveSend.subscribe(async () => {
		await send("approve", [rhoAddr, MAX_UINT], cTokenAddr);
		app.ports.enableReceiver.send(true);
	});

	app.ports.isApprovedCall.subscribe(async () => {
 		const [allowance] = await call("allowance", [ethereum.selectedAddress, rhoAddr], cTokenAddr);
 		app.ports.enableReceiver.send(!bn(allowance).isZero());
	});

	app.ports.supplyToCTokensCall.subscribe(async (underlyingAmt) => {
		const weiAmt = bn(underlyingAmt).times(DAI_DEC).toFixed(0);
		const [cTokens] = await call("toCTokens", [weiAmt], rhoLensAddr);
		app.ports.supplyToCTokensReceiver.send(fromCTokenWei(cTokens).toFixed(5));
	});

	app.ports.supplyCTokensSend.subscribe(async (supplyAmt) => {
		const supplyWei = toCTokenWei(supplyAmt);
		await send("supply", [supplyWei], rhoAddr);
	});

	const orderInfo = async ([userPayingFixed, notionalAmount]) => {
		const weiAmt = bn(notionalAmount).times(DAI_DEC).toFixed(0);
		const [swapRate, ctokens] = await call("getHypotheticalOrderInfo", [userPayingFixed, weiAmt], rhoLensAddr);
		const swapRateFixed = fromWei(swapRate).times(BLOCKS_PER_YEAR).toFixed(PRECISION);
		const underlyingAmt = fromWei(await call("toUnderlying", [ctokens], rhoLensAddr)).toFixed(PRECISION);
		const cTokenAmt = fromCTokenWei(ctokens).toFixed(PRECISION);
		return [swapRateFixed, cTokenAmt, underlyingAmt];
	};

	app.ports.orderInfo.subscribe(async (args) => {
		app.ports.orderInfoReceiver.send(await orderInfo(args));
	});

	app.ports.openSwapSend.subscribe(async ([userPayingFixed, notionalAmount]) => {
		const [swapRateFixed, _cTokenAmt, _underlyingAmt] = await orderInfo(args)
		if (userPayingFixed) {
			const rateBound = bn(swapRateFixed).times(1.1).toFixed();
			await send("openPayFixedSwap", notionalAmount, rateBound);
		} else {
			const rateBound = bn(swapRateFixed).times(.9).toFixed();
			console.log(rateBound)
			await send("openReceiveFixedSwap", notionalAmount, rateBound);
		}
	}
}

