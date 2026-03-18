const { onRequest } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

exports.analyzeFood = onRequest(
  { secrets: [GEMINI_API_KEY] },
  async (req, res) => {
  try {
    const { imageBase64, detailedAnalysis, language } = req.body;

    const genAI = new GoogleGenerativeAI(GEMINI_API_KEY.value());
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

    const languageInstruction = {
      '한국어': '한국어로 답해줘.',
      'English': 'Answer in English.',
      '日本語': '日本語で答えてください。',
    }[language] ?? '한국어로 답해줘.';

    const basePrompt = detailedAnalysis
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
         - 지방:`;

    const result = await model.generateContent([
      { inlineData: { data: imageBase64, mimeType: "image/jpeg" } },
      { text: `${languageInstruction}\n${basePrompt}` },
    ]);

    res.json({ result: result.response.text() });

  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});