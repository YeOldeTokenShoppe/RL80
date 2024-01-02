require('dotenv').config({ path: '../.env' });
const app = express();
app.use(express.static('public')); // Assuming your HTML file is in a directory named 'public'`

// MongoDB setup
const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

// Ethereum setup
const provider = new ethers.JsonRpcProvider('https://sepolia.infura.io/v3/8fda6cbb77cb4fdbb31f040686992fea');
const contractAddress = '0x30a8e8C05f83dEC581DE70C83f5Bf7bC2AdfEA07';// final sepolia contract address
const contractAbi = [{
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "address",
        "name": "burnerAddress",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
      },
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "timestamp",
        "type": "uint256"
      }
    ],
    "name": "TokensBurned",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "requestId",
        "type": "uint256"
      },
      {
        "indexed": false,
        "internalType": "uint256[]",
        "name": "randomWords",
        "type": "uint256[]"
      },
      {
        "indexed": true,
        "internalType": "uint256",
        "name": "timestamp",
        "type": "uint256"
      }
    ],
    "name": "RequestFulfilled",
    "type": "event"
  }
  
  
  ]; // Your contract ABI
const contract = new ethers.Contract(contractAddress, contractAbi, provider);

/// Connect to MongoDB when server starts
client.connect().then(() => {
    console.log('Connected to MongoDB');
}).catch(error => {
    console.error(`Error connecting to MongoDB: ${error}`);
});

// Listen to Ethereum contract events and store in MongoDB
async function listenToEvents() {
    const database = client.db("CANDL");
    const tokensBurnedCollection = database.collection("tokensBurned");
    const requestsFulfilledCollection = database.collection("requestsFulfilled");

    contract.on("TokensBurned", async (burnerAddress, amount, timestamp) => {
        console.log(`TokensBurned event: ${burnerAddress} burned ${amount} tokens at ${timestamp}`);
        await tokensBurnedCollection.insertOne({ burnerAddress, amount, timestamp });
    });

    contract.on("RequestFulfilled", async (requestId, randomWords, timestamp) => {
        console.log(`RequestFulfilled event: Request ${requestId} fulfilled with random words ${randomWords} at ${timestamp}`);
        await requestsFulfilledCollection.insertOne({ requestId, randomWords, timestamp });
    });
}

// Start listening to Ethereum events
listenToEvents();


// Start the Express server
const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});
process.on('SIGINT', closeDatabaseConnection);
process.on('SIGTERM', closeDatabaseConnection);

function closeDatabaseConnection() {
    client.close().then(() => {
        console.log('MongoDB connection closed');
        process.exit(0);
    });
}