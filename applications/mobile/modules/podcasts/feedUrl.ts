// LOFI-FORK: the podcasts section's feed link reader (see FORK.md).

const NOT_A_LINK = "That doesn't look like a web link."

// scheme://[login@]host[:port][/path][?query][#fragment]
const LINK = /^(https?):\/\/([^/?#\s]+)([/?][^\s#]*)?(#\S*)?$/i
const HOST = /^[\p{L}\p{N}-]+(\.[\p{L}\p{N}-]+)+(:\d{1,5})?$/u

/**
 * Turns what a listener pasted into one web address per feed: trimmed, with
 * `feed://`, `itpc://`, `pcast://` and a missing scheme read as https, `http://`
 * kept, the host in lower case and no fragment. Two spellings of one feed come
 * out equal. Throws a message to read when it is not a web link.
 *
 * Plain string handling on purpose: React Native's `URL` is not complete.
 */
export function normalizeFeedUrl(input: string): string {
  let text = input.trim()
  if (text === "") throw new Error("Paste a podcast link.")

  text = text.replace(/^(?:feed|itpc|pcast):(?=https?:\/\/)/i, "")
  text = text.replace(/^(?:feed|itpc|pcast):\/\//i, "https://")
  if (text.startsWith("//")) text = `https:${text}`
  else if (
    !/^[a-z][a-z0-9+.-]*:/i.test(text) ||
    /^[^/?#]*:\d+(?:[/?#]|$)/.test(text)
  ) {
    // No scheme (a port after the host is not a scheme).
    text = `https://${text}`
  }

  const match = LINK.exec(text)
  if (!match) throw new Error(NOT_A_LINK)
  const [, scheme, authority = "", rest = ""] = match
  const at = authority.lastIndexOf("@")
  const login = at >= 0 ? authority.slice(0, at + 1) : ""
  const host = (at >= 0 ? authority.slice(at + 1) : authority).toLowerCase()
  if (!HOST.test(host)) throw new Error(NOT_A_LINK)
  return `${(scheme ?? "https").toLowerCase()}://${login}${host}${rest.startsWith("/") ? rest : `/${rest}`}`
}
