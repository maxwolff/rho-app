import "regenerator-runtime/runtime";
import "../build-css/main.css";
import { Elm } from "./Main.elm";
import { makeWeb3Ports, makeStaticPorts } from "./web3Ports.js";

const defaultChainId = process.env.ELM_APP_DEFAULT_CHAIN_ID || "0x1";
const defaultNetwork = process.env.ELM_APP_DEFAULT_NETWORK || "mainnet";

const app = Elm.Main.init({
	node: document.getElementById("root"),
	flags: {
		defaultNetwork: defaultNetwork,
		duration: process.env.ELM_APP_DURATION_DAYS || "7",
		underlying: process.env.ELM_APP_UNDERLYING || "DAI",
		collateral: process.env.ELM_APP_COLLATERAL || "cDAI",
	},
});

if (window.ethereum) {
	window.ethereum.on("chainChanged", (chainId) => {
		window.location.reload();
	});

	window.ethereum.on("accountsChanged", async (accounts) => {
		window.location.reload();
		await subWeb3();
	});
} else {
	app.ports.connectReceiver.send(["none", ""]);
}

const netMap = {
	"0xNaN": { name: "development", host: "http://localhost:8545" },
	"0x1": {"name": "mainnet", "host": "https://mainnet-eth.compound.finance"},
	"0x2a": { name: "kovan", host: "https://kovan-eth.compound.finance" },
};

const getContractAddresses = (networkName) => {
	return require(`../public/networks/${networkName}.json`);
};

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
};

const subWeb3 = async () => {
	return useMetamask((config, ethereum) => {
		if (ethereum.selectedAddress == undefined) {
			app.ports.connectReceiver.send(["unconnected", ""]);
		} else {
			app.ports.connectReceiver.send([
				config.name,
				ethereum.selectedAddress,
			]);
			makeWeb3Ports(ethereum, app, getContractAddresses(config.name));
		}
	});
};

app.ports.isConnected.subscribe(async () => {
	await subWeb3();
});

app.ports.connect.subscribe(async () => {
	await useMetamask(async (config, ethereum) => {
		await ethereum.request({ method: "eth_requestAccounts" });
		makeWeb3Ports(ethereum, app, getContractAddresses(config.name));
		app.ports.connectReceiver.send([config.name, ethereum.selectedAddress]);
	});
});

const addrs = getContractAddresses(defaultNetwork);
const host = netMap[defaultChainId].host;
makeStaticPorts(host, app, addrs);
