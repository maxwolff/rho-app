import { ethers } from "ethers";

export const i = new ethers.utils.Interface([
	// erc20
	"function allowance(address, address) returns (uint)",
	"function approve(address, uint256)",
	"function balanceOf(address) returns (uint)",

	//rhoLens
	"function toCTokens(uint underlyingAmount) returns (uint cTokenAmount)",
	"function toUnderlying(uint cTokenAmt) returns (uint underlyingAmount)",
	"function getHypotheticalOrderInfo(bool userPayingFixed, uint notionalAmount) returns (uint swapFixedRateMantissa, uint userCollateralCTokens, uint userCollateralUnderlying, bool protocolIsCollateralized)",

	// rho
	"function supply(uint cTokenSupplyAmount)",
	"function openPayFixedSwap(uint notionalAmount, uint maximumFixedRateMantissa) returns (bytes32 swapHash)",
	"function openReceiveFixedSwap(uint notionalAmount, uint minFixedRateMantissa) returns (bytes32 swapHash)",
	"function supplyAccounts(address) returns (uint amount, uint lastBlock, uint index)",
	"function close(bool userPayingFixed, uint benchmarkIndexInit, uint initBlock, uint swapFixedRateMantissa, uint notionalAmount, uint userCollateralCTokens, address owner)",
	"event OpenSwap(bytes32 indexed swapHash, bool userPayingFixed, uint benchmarkIndexInit, uint initBlock, uint swapFixedRateMantissa, uint notionalAmount, uint userCollateralCTokens, address indexed owner)",
	"event CloseSwap(bytes32 indexed swapHash, address indexed owner, uint userPayout, uint benchmarkIndexFinal)"
]);

export const bn = (str) => {
	return ethers.BigNumber.from(str);
};

export const MAX_UINT = bn(2)
	.pow(256)
	.sub(1)
	.toString();
const DAI_DEC = bn(10).pow(18);
const CTOKEN_DEC = bn(10).pow(8);
const BLOCKS_PER_YEAR = 2102400;

// (bn | str): fn
export const fn = (bnOrStr) => {
	return ethers.FixedNumber.from(bnOrStr);
};

// (bn | str): fn
export const toAmt = (wei) => {
	return fn(wei).divUnsafe(fn(DAI_DEC));
};

// (bn | str): fn
export const toCTokenAmt = (cTokenWei) => {
	return fn(cTokenWei).divUnsafe(fn(CTOKEN_DEC));
};

export const toCTokenWeiStr = (cTokenAmt) => {
	return fn(cTokenAmt)
		.mulUnsafe(fn(CTOKEN_DEC))
		.toString()
		.split(".")[0];
};

export const toWeiStr = (amt) => {
	return fn(amt)
		.mulUnsafe(fn(DAI_DEC))
		.toString()
		.split(".")[0];
};

export const toPercFromBlockMantissa = (wei) => {
	return toAmt(wei.mul(BLOCKS_PER_YEAR).mul(100))
		.round(3)
		.toString();
};
