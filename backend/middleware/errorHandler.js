// Uniform JSON errors: { error: { code, message, details? } }
const { ZodError } = require("zod");
const { AppError } = require("../utils/errors");

function notFoundHandler(req, res) {
  res.status(404).json({ error: { code: "NOT_FOUND", message: `No route for ${req.method} ${req.path}` } });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof ZodError) {
    const details = err.issues.map((i) => ({ field: i.path.join("."), message: i.message }));
    const first = details[0];
    return res.status(400).json({
      error: { code: "VALIDATION_ERROR", message: first ? `${first.field ? `${first.field}: ` : ""}${first.message}` : "Invalid request", details },
    });
  }
  if (err && err.type === "entity.parse.failed") {
    return res.status(400).json({ error: { code: "BAD_JSON", message: "Request body is not valid JSON." } });
  }
  if (err instanceof AppError) {
    const body = { code: err.code, message: err.message };
    if (err.details !== undefined) body.details = err.details;
    return res.status(err.status).json({ error: body });
  }
  console.error("[unhandled]", err);
  return res.status(500).json({ error: { code: "INTERNAL", message: "Something went wrong on the server." } });
}

module.exports = { errorHandler, notFoundHandler };
