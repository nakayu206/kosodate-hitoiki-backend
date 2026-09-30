import { type CheckResult, ModerationUnavailableError } from "./types.ts";

/** docs/API契約.md のエラー形式・コードへ対応づける。本文・APIキーはレスポンスに含めない。 */
function errorResponse(
  status: number,
  code: string,
  message: string,
  details?: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify({ error: { code, message, details } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** 判定が allow 以外のとき、対応するエラーレスポンスを返す。allow なら null。 */
export function responseForDecision(result: CheckResult): Response | null {
  if (result.decision === "reject") {
    return errorResponse(
      422,
      "MODERATION_REJECTED",
      "この内容は送信できません。表現を見直してください。",
      {
        reasons: result.reasons,
      },
    );
  }
  if (result.decision === "confirm") {
    return errorResponse(
      409,
      "MODERATION_CONFIRM_REQUIRED",
      "他の人を傷つける表現になっていないか、確認してから送信してください。",
      { reasons: result.reasons },
    );
  }
  return null;
}

/** 外部APIの障害。保存はブロックし、再試行を促す（決定済み）。 */
export function responseForError(error: unknown): Response | null {
  if (error instanceof ModerationUnavailableError) {
    return errorResponse(
      503,
      "MODERATION_UNAVAILABLE",
      "内容の確認ができませんでした。しばらくしてからもう一度お試しください。",
    );
  }
  return null;
}
