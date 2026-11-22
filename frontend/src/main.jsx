import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App.jsx";
import { LanguageProvider } from "./i18n/LanguageContext.jsx";
import { VoiceProvider } from "./voice/VoiceContext.jsx";
import "./styles/app.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <BrowserRouter>
      <LanguageProvider>
        <VoiceProvider>
          <App />
        </VoiceProvider>
      </LanguageProvider>
    </BrowserRouter>
  </React.StrictMode>
);
