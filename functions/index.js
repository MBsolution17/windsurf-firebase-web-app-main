const functions = require("firebase-functions");
const axios = require("axios");

// Récupération de la clé API depuis les configurations Firebase
const convertApiKey = functions.config().convertapi.secret;

// Fonction HTTP pour convertir un PDF en DOCX
exports.convertPdfToDocx = functions.https.onRequest(async (req, res) => {
  try {
    // Vérifie si le corps de la requête contient un PDF
    if (!req.body || !req.body.pdfData) {
      res.status(400).send({
        error: "Requête invalide. Le fichier PDF est requis.",
      });
      return;
    }

    const pdfData = req.body.pdfData;

    // Appel de l'API ConvertAPI
    const response = await axios.post(
      "https://v2.convertapi.com/convert/pdf/to/docx",
      {
        Parameters: [
          {
            Name: "File",
            FileValue: {
              Url: pdfData,
            },
          },
        ],
      },
      {
        headers: {
          Authorization: `Bearer ${convertApiKey}`,
        },
      }
    );

    // Extraction de l'URL du fichier converti
    const files = response.data && response.data.Files;
    if (!files || files.length === 0 || !files[0].Url) {
      res.status(500).send({
        error: "Erreur lors de la conversion PDF->DOCX.",
      });
      return;
    }

    const docxUrl = files[0].Url;
    res.status(200).send({ docxFileUrl: docxUrl, });
  } catch (error) {
    console.error("Erreur lors de la conversion PDF->DOCX:", error);
    res.status(500).send({
      error: "Une erreur est survenue lors de la conversion.",
    });
  }
});
