import { ethers } from "ethers";
import {
	i,
	bn,
	fn,
	toAmt,
	toCTokenAmt,
	toWeiStr,
	toCTokenWeiStr,
	toPercFromBlockMantissa,
	MAX_UINT
} from "./util";

export const makeWeb3Ports = async (ethereum, app, contractAddresses) => {
	const {
		rhoLens: rhoLensAddr,
		cToken: cTokenAddr,
		rho: rhoAddr,
	} = contractAddresses;

	const call = async (sig, args, to) => {
		const data = i.encodeFunctionData(sig, args);
		const res = await ethereum.request({
			method: "eth_call",
			params: [{ to, data }],
		});
		return i.decodeFunctionResult(sig, res);
	};

	const send = async (sig, args, to, gas = "0x7a120" /* 500k */) => {
		const data = i.encodeFunctionData(sig, args);
		return ethereum.request({
			method: "eth_sendTransaction",
			params: [{ to, data, from: ethereum.selectedAddress, gas }],
		});
	};

	app.ports.unlockedLiquidity.subscribe(async () => {
		const {
			lockedCollateral,
			supplierLiquidity,
			cTokenExchangeRate,
		} = await call("getSupplyCollateralState", [], rhoLensAddr);
		const unlocked = supplierLiquidity.sub(lockedCollateral);
		const [unlockedUnderlying] = await call("toUnderlying", [unlocked], rhoLensAddr);
		app.ports.unlockedLiquidityReceiver.send(
			toAmt(unlockedUnderlying).round(2).toString()
		);
	});

	// PORT fns receive values as strings with decimals. ie "1.5" instead of 1.5e18, so we need to scale up before sending
	app.ports.approveSend.subscribe(async () => {
		await send("approve", [rhoAddr, MAX_UINT], cTokenAddr, "0x011170"); //70k
		app.ports.enableReceiver.send(true);
	});

	app.ports.isApprovedCall.subscribe(async () => {
		if (ethereum.selectedAddress) {
			const [allowance] = await call(
				"allowance",
				[ethereum.selectedAddress, rhoAddr],
				cTokenAddr
			);
			app.ports.enableReceiver.send(!bn(allowance).isZero());
		}
	});

	app.ports.toCTokensCall.subscribe(async ([name, underlyingAmt]) => {
		const underlyingWei = toWeiStr(underlyingAmt);
		const [cTokens] = await call("toCTokens", [underlyingWei], rhoLensAddr);
		app.ports.toCTokensReceiver.send([
			name,
			toCTokenAmt(cTokens)
				.round(2)
				.toString(),
		]);
	});

	app.ports.supplyCTokensSend.subscribe(async (supplyAmt) => {
		await send("supply", [toCTokenWeiStr(supplyAmt)], rhoAddr);
	});

	app.ports.removeCTokensSend.subscribe(
		async ([removeAmt, shouldRemoveAll]) => {
			if (shouldRemoveAll) {
				await send("remove", ["0"], rhoAddr);
			} else {
				await send("remove", [toCTokenWeiStr(removeAmt)], rhoAddr);
			}
		}
	);

	app.ports.orderInfoCall.subscribe(
		async ([userPayingFixed, notionalAmount]) => {
			const notionalWei = toWeiStr(notionalAmount);

			let res;
			try {
				const [
					swapRateWei,
					ctokenWei,
					underlyingWei,
					protocolIsCollateralized,
				] = await call(
					"getHypotheticalOrderInfo",
					[userPayingFixed, notionalWei],
					rhoLensAddr
				);
				const swapRate = toPercFromBlockMantissa(swapRateWei);
				const collatDollars = toAmt(underlyingWei)
					.round(2)
					.toString();
				const collatCToken = toCTokenAmt(ctokenWei)
					.round(2)
					.toString();
				app.ports.orderInfoReceiver.send({
					swapRate,
					collatCToken,
					collatDollars,
					protocolIsCollateralized,
				});
			} catch (e) {
				console.log(e);
				// return false if 0 liqudity
				app.ports.orderInfoReceiver.send({
					swapRate: "0",
					collatCToken: "0",
					collatDollars: "0",
					protocolIsCollateralized: false,
				});
			}
		}
	);

	app.ports.openSwapSend.subscribe(
		async ([userPayingFixed, notionalAmount]) => {
			const notionalWei = toWeiStr(notionalAmount);
			const [swapRateWei, _ctokens] = await call(
				"getHypotheticalOrderInfo",
				[userPayingFixed, notionalWei],
				rhoLensAddr
			);
			if (userPayingFixed) {
				const rateBound = swapRateWei.mul(11).div(10);
				await send(
					"openPayFixedSwap",
					[notionalWei, rateBound],
					rhoAddr
				);
			} else {
				const rateBound = swapRateWei.mul(9).div(10);
				await send(
					"openReceiveFixedSwap",
					[notionalWei, rateBound],
					rhoAddr
				);
			}
		}
	);

	// hypothetical $ supply amount
	app.ports.isAboveLimit.subscribe(async (amt) => {
		let [ {supplierLiquidity}, [liquidityLimit]] = await Promise.all([
			call("getSupplyCollateralState", [], rhoLensAddr),
			call("liquidityLimit", [], rhoAddr)
		]);
		const [supplyCTokens] = await call("toUnderlying", [amt], rhoLensAddr);
		const supplyCTokenWei = bn(toCTokenWeiStr(supplyCTokens));
		const isAboveLimit = liquidityLimit.lt(supplierLiquidity.add(supplyCTokens));
		app.ports.aboveLimitReceiver.send(isAboveLimit) 
	});

	app.ports.supplyBalance.subscribe(async () => {
		let [{ amount: supplyCTokensWei }, [userCTokenBal]] = await Promise.all([
			call("supplyAccounts", [ethereum.selectedAddress], rhoAddr),
			call("balanceOf", [ethereum.selectedAddress], cTokenAddr),
		]);

		const supplyBalanceCTokens = toCTokenAmt(supplyCTokensWei)
			.round(3)
			.toString();

		const [supplyUnderlyingWei] = await call(
			"toUnderlying",
			[supplyCTokensWei],
			rhoLensAddr
		);
		const supplyBalanceUnderlying = toAmt(supplyUnderlyingWei)
			.round(2)
			.toString();

		const userCTokenBalance = toCTokenAmt(userCTokenBal)
			.round(3)
			.toString();

		app.ports.userBalancesReceiver.send({
			supplyBalanceCTokens,
			supplyBalanceUnderlying,
			userCTokenBalance
		});
	});

	const getTimestampFromBlock = async (bn) => {
		const provider = new ethers.providers.Web3Provider(ethereum);
		const blockHeader = await provider.getBlock(Number(bn));
		const timestamp = blockHeader.timestamp.toString();
		let delta = Math.floor(Date.now() / 1000) - timestamp;

		const days = Math.floor(delta / 86400);
		delta -= days * 86400;
		const hrs = +(delta / 3600).toFixed(1);
		if (days == 0) {
			return `${hrs} hrs`;
		} else {
			return `${days} days, ${hrs} hrs`;
		}
	};

	const argsToDisplay = async (args) => {
		const timeAgo = await getTimestampFromBlock(args.initBlock);
		return {
			swapHash: args.swapHash,
			timeAgo,
			notional: toAmt(args.notionalAmount).toString(),
			rate: toPercFromBlockMantissa(args.swapFixedRateMantissa),
			userPayingFixed: args.userPayingFixed,
			userPayout: null,
		};
	};

	const processEvents = async (allEvents) => {
		const displayEvents = {};
		const closableEvents = {};
		for (let e of allEvents) {
			const { args, event } = e;
			const swapHash = args.swapHash;
			if (event == "OpenSwap") {
				displayEvents[swapHash] = await argsToDisplay(args);
				closableEvents[swapHash] = args;
			} else {
				displayEvents[swapHash].userPayout = toAmt(args.userPayout)
					.round(4)
					.toString();
				delete closableEvents[swapHash];
			}
		}
		return [displayEvents, closableEvents];
	};

	app.ports.swapHistory.subscribe(async () => {
		const provider = new ethers.providers.Web3Provider(ethereum);
		const rho = new ethers.Contract(rhoAddr, i, provider);

		const openFilter = rho.filters.OpenSwap(
			...Array(7).concat(ethereum.selectedAddress)
		); // add some blanks for non indexed params
		const openEvents = await rho.queryFilter(openFilter);

		const closeFilter = rho.filters.CloseSwap(
			null,
			ethereum.selectedAddress
		);
		const closeEvents = await rho.queryFilter(closeFilter);

		const allEvents = openEvents.concat(closeEvents);
		const closeArgsArr = [];
		const [displayEvents, closeableSwaps] = await processEvents(allEvents);

		app.ports.swapHistoryReceiver.send(Object.values(displayEvents));
		app.ports.closeSwapSend.subscribe(async (swapHash) => {
			const swap = closeableSwaps[swapHash];
			const args = [
				swap.userPayingFixed,
				swap.benchmarkIndexInit.toString(),
				swap.initBlock.toString(),
				swap.swapFixedRateMantissa.toString(),
				swap.notionalAmount.toString(),
				swap.userCollateralCTokens.toString(),
				swap.owner,
			];
			await send("close", args, rhoAddr);
		});
	});
};

export const makeStaticPorts = async (host, app, contractAddresses) => {
	const abi = [
		"function getSupplyCollateralState() returns (uint lockedCollateral, uint supplierLiquidity, uint cTokenExchangeRate)",
		"function getMarkets() returns (uint notionalReceivingFixed, uint notionalPayingFixed, uint avgFixedRateReceiving, uint avgFixedRatePaying)",
	];

	const provider = new ethers.providers.JsonRpcProvider(host);
	const {
		rhoLens: rhoLensAddr,
		cToken: cTokenAddr,
		rho: rhoAddr,
	} = contractAddresses;
	const rho = new ethers.Contract(rhoAddr, abi, provider);
	const rhoLens = new ethers.Contract(rhoLensAddr, abi, provider);

	app.ports.getMarkets.subscribe(async () => {
		const promises = [
			rhoLens.callStatic.getSupplyCollateralState(),
			rhoLens.callStatic.getMarkets(),
		];
		const [[lc, sl], [nrf, npf, afrr, afrp]] = await Promise.all(promises);
		const notionalReceivingFixed = toAmt(nrf)
			.round(2)
			.toString();
		const notionalPayingFixed = toAmt(npf)
			.round(2)
			.toString();
		const avgFixedRateReceiving = toAmt(afrr)
			.round(2)
			.toString();
		const avgFixedRatePaying = toAmt(afrp)
			.round(2)
			.toString();
		const supplierLiquidity = toCTokenAmt(sl)
			.round(2)
			.toString();
		const lockedCollateral = toCTokenAmt(lc)
			.round(2)
			.toString();

		app.ports.getMarketsReceiver.send({
			notionalReceivingFixed,
			notionalPayingFixed,
			avgFixedRatePaying,
			avgFixedRateReceiving,
			supplierLiquidity,
			lockedCollateral,
		});
	});
};
