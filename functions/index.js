const { onRequest } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

exports.analyzeFood = onRequest(
  { secrets: [GEMINI_API_KEY] },
  async (req, res) => {
  try {
    const { imageBase64, detailedAnalysis, language, aiModel } = req.body;

    const genAI = new GoogleGenerativeAI(GEMINI_API_KEY.value());
    const model = genAI.getGenerativeModel({
      model: aiModel || "gemini-2.5-flash-lite" // 없으면 기본값
    });

    const basePrompt = {
      '한국어': detailedAnalysis
        ? `이 음식 사진을 최대한 정밀하게 분석해줘.
           음식 이름:
           예상 칼로리:
           주요 영양소:
           - 탄수화물:
           - 단백질:
           - 지방:
           - 나트륨:
           - 식이섬유:
           추가 정보: 재료, 조리법, 혈당지수(GI) 등 상세하게`
        : `이 음식 사진을 분석해줘. 다음 형식으로 답해줘:
           음식 이름:
           예상 칼로리:
           주요 영양소:
           - 탄수화물:
           - 단백질:
           - 지방:`,

      'English': detailedAnalysis
        ? `Analyze this food photo in detail.
           Food name:
           Estimated calories:
           Main nutrients:
           - Carbohydrates:
           - Protein:
           - Fat:
           - Sodium:
           - Dietary fiber:
           Additional info: ingredients, cooking method, glycemic index (GI), etc.`
        : `Analyze this food photo. Reply in this format:
           Food name:
           Estimated calories:
           Main nutrients:
           - Carbohydrates:
           - Protein:
           - Fat:`,

      '日本語': detailedAnalysis
        ? `この料理の写真を詳しく分析してください。
           料理名：
           推定カロリー：
           主な栄養素：
           - 炭水化物：
           - タンパク質：
           - 脂質：
           - ナトリウム：
           - 食物繊維：
           追加情報：材料、調理法、グリセミック指数（GI）など`
        : `この料理の写真を分析してください。次の形式で答えてください：
           料理名：
           推定カロリー：
           主な栄養素：
           - 炭水化物：
           - タンパク質：
           - 脂質：`,
    }[language ?? '한국어'];

    const result = await model.generateContent([
      { inlineData: { data: imageBase64, mimeType: "image/jpeg" } },
      { text: basePrompt },
    ]);

    res.json({ result: result.response.text() });

  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});