// The water runs here, off the page's main thread: scrolling and clicks never wait for the marbling.
import { createEngine } from './engine.js';

const engine = createEngine((msg, transfer) => self.postMessage(msg, transfer || []));
self.onmessage = e => engine.handle(e.data);
