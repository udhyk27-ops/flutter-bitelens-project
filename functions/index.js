const { onRequest } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAppCheck } = require("firebase-admin/app-check");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// ── 비용/남용 방어 설정 ────────────────────────────────────────────────
// 요청 본문(base64) 상한: 약 6MB 이미지까지 허용(그 이상은 413 거부).
const MAX_IMAGE_B64 = 8_000_000;
// 클라이언트가 임의의 고비용 모델을 지정하지 못하도록 허용 모델을 제한.
// (요청 body의 aiModel이 목록에 없으면 기본 모델로 강제)
const ALLOWED_MODELS = new Set([
  "gemini-2.5-flash-lite",
  "gemini-2.5-flash",
  "gemini-2.0-flash",
  "gemini-2.0-flash-lite",
]);
const DEFAULT_MODEL = "gemini-2.5-flash-lite";

// 클라이언트가 실제 이미지 포맷을 알려주면 그에 맞는 MIME으로 Gemini에 전달.
// (미지정/미허용 시 기본 jpeg — 클라이언트는 보통 JPEG로 재인코딩해 보낸다.)
// Gemini가 지원하는 이미지 MIME 목록.
const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);
const DEFAULT_MIME = "image/jpeg";

// Firebase Admin 초기화 (App Check 검증에 필요)
initializeApp();

exports.analyzeFood = onRequest(
  {
    secrets: [GEMINI_API_KEY],
    // 인스턴스 폭증에 따른 요금 폭탄 방지(동시 인스턴스 상한)
    maxInstances: 10,
    memory: "512MiB",
    timeoutSeconds: 60,
    // concurrency 미지정: 기본값 사용(명시하면 CPU>=1 제약으로 배포 실패 가능)
    // region 미지정: 기본 us-central1 유지(기존 호출 URL 불변)
  },
  async (req, res) => {
    // POST 외 메서드는 즉시 차단(프로빙/스팸이 작업을 유발하지 않도록)
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    // ── App Check 검증 ──────────────────────────────────────────────────
    // 등록된 앱(Play Integrity / DeviceCheck)에서 보낸 요청만 통과시킵니다.
    // 개발 시 디버그 토큰 설정:
    //   1) kDebugMode에서 앱 실행 → 콘솔에 출력되는 UUID 복사
    //   2) Firebase 콘솔 > App Check > 앱 > 디버그 토큰 관리 > UUID 등록
    const appCheckToken = req.header("X-Firebase-AppCheck");
    if (!appCheckToken) {
      res.status(401).json({ error: "Unauthorized: App Check token required" });
      return;
    }
    try {
      await getAppCheck().verifyToken(appCheckToken);
    } catch (err) {
      console.warn("App Check verification failed:", err.message);
      res.status(401).json({ error: "Unauthorized: Invalid App Check token" });
      return;
    }
    // ───────────────────────────────────────────────────────────────────

    try {
      const { imageBase64, imageMimeType, detailedAnalysis, language, aiModel } =
        req.body;

      if (typeof imageBase64 !== "string" || imageBase64.length === 0) {
        res.status(400).json({ error: "이미지 데이터가 필요합니다." });
        return;
      }
      if (imageBase64.length > MAX_IMAGE_B64) {
        res.status(413).json({ error: "이미지 용량이 너무 큽니다. 더 작은 사진을 사용해주세요." });
        return;
      }

      // 클라이언트가 알려준 포맷을 허용 목록으로 검증(없으면 기본 jpeg).
      // 잘못된 MIME으로 라벨링하면 Gemini 디코딩 실패로 이어질 수 있다.
      const mimeType =
        typeof imageMimeType === "string" && ALLOWED_MIME.has(imageMimeType)
          ? imageMimeType
          : DEFAULT_MIME;

      // 클라이언트가 보낸 모델을 허용 목록으로 제한(고비용 모델 강제 방지)
      const requestedModel =
        typeof aiModel === "string" && ALLOWED_MODELS.has(aiModel)
          ? aiModel
          : DEFAULT_MODEL;

      // ── 구조화 출력 스키마 ─────────────────────────────────────────────
      // Gemini가 자연어 대신 정해진 JSON을 반환하도록 강제한다.
      // 단위: calories=kcal(정수), 탄수화물/단백질/지방/식이섬유=g, 나트륨=mg
      const properties = {
        foodName: { type: "string" },
        calories: { type: "integer" },
        carbohydrates: { type: "number" },
        protein: { type: "number" },
        fat: { type: "number" },
        note: { type: "string" },
      };
      const required = ["foodName", "calories", "carbohydrates", "protein", "fat"];
      if (detailedAnalysis) {
        properties.sodium = { type: "number" };
        properties.fiber = { type: "number" };
      }

      const genAI = new GoogleGenerativeAI(GEMINI_API_KEY.value());
      const model = genAI.getGenerativeModel({
        model: requestedModel,
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: { type: "object", properties, required },
        },
      });

      const langName =
        { "한국어": "Korean", "English": "English", "日本語": "Japanese" }[
          language ?? "한국어"
        ] || "Korean";

      const prompt =
        `You are a nutrition analysis assistant. Analyze the food in this photo and ` +
        `fill the provided JSON schema. Units: calories in kcal (integer); ` +
        `carbohydrates, protein, fat${detailedAnalysis ? ", fiber" : ""} in grams` +
        `${detailedAnalysis ? "; sodium in milligrams" : ""}. ` +
        `Estimate for a single typical serving shown in the photo. ` +
        `Write "foodName" and ${detailedAnalysis
          ? 'a detailed "note" (key ingredients, cooking method, glycemic index, etc.)'
          : 'a brief one-line "note"'} in ${langName}. ` +
        `If a value is uncertain, provide your best numeric estimate. ` +
        `If the image does not contain food, set foodName accordingly and use 0 for the numbers.`;

      // ── Gemini 호출 ────────────────────────────────────────────────────
      // 레이트리밋/일시 장애는 클라이언트가 재시도·안내를 구분할 수 있도록
      // 상태코드를 나눠서 반환한다(전부 500으로 뭉개지 않음).
      let result;
      try {
        result = await model.generateContent([
          { inlineData: { data: imageBase64, mimeType } },
          { text: prompt },
        ]);
      } catch (err) {
        const status = err?.status ?? err?.response?.status;
        if (status === 429) {
          console.warn("Gemini rate limited:", err.message);
          res.status(429).json({ error: "서버가 혼잡합니다. 잠시 후 다시 시도해주세요." });
          return;
        }
        if (status === 500 || status === 503) {
          console.warn("Gemini unavailable:", err.message);
          res.status(503).json({
            error: "분석 서비스가 일시적으로 불안정합니다. 잠시 후 다시 시도해주세요.",
          });
          return;
        }
        throw err; // 그 외는 아래 일반 500 처리
      }

      const response = result.response;

      // 안전 필터 등으로 응답이 차단된 경우: 재시도해도 소용없으므로 별도 안내.
      const blockReason = response?.promptFeedback?.blockReason;
      if (blockReason) {
        console.warn("Gemini blocked prompt:", blockReason);
        res.status(422).json({ error: "이 사진은 분석할 수 없습니다. 다른 사진을 사용해주세요." });
        return;
      }

      // 빈 candidate/안전 차단 시 text()가 throw → 422로 구분.
      let text;
      try {
        text = response.text();
      } catch (err) {
        console.warn("Gemini empty/blocked candidate:", err.message);
        res.status(422).json({ error: "이 사진은 분석할 수 없습니다. 다른 사진을 사용해주세요." });
        return;
      }

      // 스키마 위반 JSON이 그대로 클라이언트(FoodAnalysis.parse)에서 터지지 않도록
      // 서버에서 한 번 파싱·필수 필드 검증 후 통과시킨다.
      let parsed;
      try {
        parsed = JSON.parse(text);
      } catch (err) {
        console.error("Gemini returned non-JSON:", (text || "").slice(0, 200));
        res.status(502).json({ error: "분석 결과를 해석하지 못했습니다. 다시 시도해주세요." });
        return;
      }
      const missing = required.filter(
        (k) => parsed[k] === undefined || parsed[k] === null
      );
      if (missing.length > 0) {
        console.error("Gemini response missing fields:", missing.join(", "));
        res.status(502).json({ error: "분석 결과가 올바르지 않습니다. 다시 시도해주세요." });
        return;
      }

      // 클라이언트는 result 문자열을 JSON으로 파싱한다(FoodAnalysis.parse).
      res.json({ result: text });

    } catch (e) {
      // 내부 오류 상세는 서버 로그에만 남기고, 클라이언트에는 일반 메시지만 반환
      console.error(e);
      res.status(500).json({ error: "분석 중 오류가 발생했습니다." });
    }
  }
);
