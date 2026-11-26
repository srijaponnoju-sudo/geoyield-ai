import { Routes, Route, Navigate, useLocation } from "react-router-dom";
import { useEffect } from "react";
import Navbar from "./components/Navbar.jsx";
import Footer from "./components/Footer.jsx";
import Landing from "./pages/Landing.jsx";
import Dashboard from "./pages/Dashboard.jsx";
import CropRecommendation from "./pages/CropRecommendation.jsx";
import YieldPrediction from "./pages/YieldPrediction.jsx";
import CropHealth from "./pages/CropHealth.jsx";
import FertilizerEvaluation from "./pages/FertilizerEvaluation.jsx";
import History from "./pages/History.jsx";
import About from "./pages/About.jsx";
import ProfitMode from "./pages/ProfitMode.jsx";
import Schemes from "./pages/Schemes.jsx";
import "./i18n/translations_upgrade.js";
import "./styles/upgrade.css";
import VoiceAssistant from "./voice/VoiceAssistant.jsx";

function ScrollTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);
  return null;
}

export default function App() {
  return (
    <>
      <ScrollTop />
      <Navbar />
      <main>
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/crop-recommendation" element={<CropRecommendation />} />
          <Route path="/yield-prediction" element={<YieldPrediction />} />
          <Route path="/crop-health" element={<CropHealth />} />
          <Route path="/fertilizer" element={<FertilizerEvaluation />} />
          <Route path="/profit" element={<ProfitMode />} />
          <Route path="/schemes" element={<Schemes />} />
          <Route path="/history" element={<History />} />
          <Route path="/about" element={<About />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      <Footer />
      <VoiceAssistant />
    </>
  );
}
