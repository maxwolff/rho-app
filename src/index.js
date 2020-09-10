import './main.css';
import { Elm } from './Main.elm';
import networks from '../public/networks/development.json';
import abis from '../public/abis.json';

var Contract = require('web3-eth-contract');

const app = Elm.Main.init({
	node: document.getElementById('root')
});

// const bn = num => {
// 	return ethers.BigNumber.from(num).toString();
// };

const doConnect = () => {
	return Promise.resolve().then(function () {
		const eth = window.ethereum;
		if (eth) {
			return Promise.resolve().then(function () {
				return eth.request({ method: 'eth_requestAccounts' });
			}).then(function () {
				subWeb3("http://localhost:8545");
				app.ports.networkReceiver.send(eth.chainId);
			});
		}
	}).then(function () {});
};

app.ports.connect.subscribe(message => {
	return Promise.resolve().then(function () {
		console.log('Port emitted a new message: ' + message);
		return doConnect();
	}).then(function () {});
});

//reload page on chainChanged
window.ethereum.on('chainChanged', chainId => {
	window.location.reload();
});

const subWeb3 = provider => {
	return Promise.resolve().then(function () {
		Contract.setProvider(provider);
		const rhoLens = new Contract(abis.rhoLens, networks.rhoLens);
		app.ports.orderInfo.subscribe(msg => {
			return Promise.resolve().then(function () {
				return rhoLens.methods.getHypotheticalOrderInfo(true, '100000000000').call();
			}).then(function (_resp) {
				const res = _resp;
				console.log(res);
			});
		});
	});
};
