const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");

const app = express();
app.use(bodyParser.json());

const OPENAI_API_KEY = "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";

app.post("/chatgpt", async (req, res) => {
  try {
    const { message } = req.body;

    const response = await axios.post(
      "https://api.openai.com/v1/completions",
      {
        model: "text-davinci-003",
        prompt: message,
        max_tokens: 150,
      },
      {
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${OPENAI_API_KEY}`,
        },
      }
    );

    res.json({ response: response.data.choices[0].text.trim() });
  } catch (error) {
    console.error(error);
    res.status(500).send("Erreur lors de la communication avec ChatGPT.");
  }
});

app.listen(3000, () => {
  console.log("Serveur démarré sur le port 3000.");
});
