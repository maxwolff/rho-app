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

const doConnect = async () => {
	const eth = window.ethereum;
	if (eth) {
		await eth.request({method: 'eth_requestAccounts'});
		subWeb3("http://localhost:8545");
		app.ports.networkReceiver.send(eth.chainId);
	}
};

app.ports.connect.subscribe(async (message) => {
  console.log('Port emitted a new message: ' + message);
  await doConnect();
});

//reload page on chainChanged
window.ethereum.on('chainChanged', (chainId) => {
  window.location.reload();
});

const subWeb3 = async (provider) => {
	Contract.setProvider(provider)
	const rhoLens = new Contract(abis.rhoLens, networks.rhoLens);
	app.ports.orderInfo.subscribe(async (msg) => {
		const res = await rhoLens.methods.getHypotheticalOrderInfo(true, '100000000000').call();
		console.log(res)
	});
}
