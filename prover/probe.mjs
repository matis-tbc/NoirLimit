import { Barretenberg, Fr } from '@aztec/bb.js';
const bb = await Barretenberg.new({ threads: 1 });
const proto = Object.getPrototypeOf(bb);
const methods = Object.getOwnPropertyNames(proto);
console.log('total methods:', methods.length);
console.log('hash methods:', methods.filter(n => /hash|pedersen|poseidon/i.test(n)));
console.log('first 30 methods:', methods.slice(0,30));
await bb.destroy?.();
