// Application error carrying an HTTP status and a stable machine-readable code.
// Serialized by middleware/errorHandler.js as { error: { code, message, details? } }.
class AppError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.name = "AppError";
    this.status = status;
    this.code = code;
    if (details !== undefined) this.details = details;
  }
}

const badRequest = (code, message, details) => new AppError(400, code, message, details);
const notFound = (code, message) => new AppError(404, code, message);
const conflict = (code, message, details) => new AppError(409, code, message, details);
const forbidden = (code, message) => new AppError(403, code, message);

module.exports = { AppError, badRequest, notFound, conflict, forbidden };
