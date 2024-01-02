document.addEventListener("DOMContentLoaded", function() {
    const flame = document.querySelector(".flame");
    const glow = document.querySelector(".glow");
    const blinkingGlow = document.querySelector(".blinking-glow");
    const toggleButton = document.getElementById("toggleFlame");

    // Initially hide the flame and its associated elements
    flame.style.display = "none";
    glow.style.display = "none";
    blinkingGlow.style.display = "none";

    toggleButton.addEventListener("click", function() {
        if (flame.style.display === "none") {
            flame.style.display = "block";
            glow.style.display = "block";
            blinkingGlow.style.display = "block";
        } else {
            flame.style.display = "none";
            glow.style.display = "none";
            blinkingGlow.style.display = "none";
        }
    });
});



let btn = document.querySelector("button");
setTimeout(() => {
    btn.classList.remove("active");
},1400);

document.querySelector('#toggleFlame').addEventListener('click', function() {
    document.body.classList.toggle('gradient-background');
  });

  const express = require('express');
const { MongoClient } = require('mongodb');
const { ethers } = require('ethers');






const app = express();
app.use(express.static('public')); // Assuming your HTML file is in a directory named 'public'`

// MongoDB setup
const uri = "mongodb+srv://mpaulsonx:XeLDP3kjuBPkt6vT@cluster0.nxrcrio.mongodb.net/";
const client = new MongoClient(uri);

// Ethereum setup
const provider = new ethers.JsonRpcProvider('https://sepolia.infura.io/v3/8fda6cbb77cb4fdbb31f040686992fea');
const contractAddress = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const contractAbi = [{
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "address",
        "name": "burner",
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
async function listenToLotteryEntries() {
    const database = client.db("CANDL");
    const collection = database.collection("Cluster0");

    contract.on("LotteryEntry", async (participant, totalEntries, timestamp) => {
        console.log(`Type of totalEntries: ${typeof totalEntries}`);
        console.log(`Value of totalEntries: ${totalEntries}`);
        const entriesCount = parseInt(totalEntries, 10);
        for (let i = 0; i < totalEntries; i++) {
            await collection.insertOne({ participant: participant, timestamp: timestamp });
        }
        console.log(`Processed ${totalEntries} entries for participant: ${participant}`);
    });
}

// API endpoint to fetch lottery entries
app.get('/api/lottery-entries', async (req, res) => {
    const database = client.db("CANDL");
    const collection = database.collection("Cluster0");
    try {
        const entries = await collection.find({}).toArray();
        console.log('Entries:', entries);
        res.json(entries);
    } catch (error) {
        console.error(`Error: ${error}`);
        res.status(500).send(`Error retrieving lottery entries: ${error}`);
    }
});

// Start listening to Ethereum events
listenToLotteryEntries();

// Start the Express server
const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});