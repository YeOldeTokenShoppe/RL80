const express = require('express');
const app = express();
const cors = require('cors');
const corsOptions = {
    origin: '*',
    optionsSuccessStatus: 200,
}
app.use(cors(corsOptions))
app.use(require('body-parser').json());