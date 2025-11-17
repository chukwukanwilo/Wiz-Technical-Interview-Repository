const express = require('express');
const { MongoClient } = require('mongodb');
const app = express();
const port = process.env.PORT || 3000;
const mongoUri = process.env.MONGO_URI || 'mongodb://mongo:27017/tasky';

let db;

async function initDb(){
  const client = new MongoClient(mongoUri, { useUnifiedTopology: true });
  await client.connect();
  db = client.db('tasky');
  await db.collection('todos').createIndex({ createdAt: 1 });
}

app.use(express.json());

app.get('/', (req, res) => res.send('Tasky sample app - connect to /todos'));

app.get('/wiz-file', (req, res) => {
  const fs = require('fs');
  const content = fs.readFileSync('/app/wizexercise.txt', 'utf8');
  res.send({ wiz: content });
});

app.get('/todos', async (req, res) => {
  const todos = await db.collection('todos').find().toArray();
  res.json(todos);
});

app.post('/todos', async (req, res) => {
  const todo = { text: req.body.text || 'no text', createdAt: new Date() };
  const r = await db.collection('todos').insertOne(todo);
  res.json({ insertedId: r.insertedId });
});

initDb().then(() => app.listen(port, () => console.log(`Listening on ${port}`))).catch(err => { console.error(err); process.exit(1); });
