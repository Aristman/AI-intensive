// Resources handler (list/read) — stub implementation
// All logs should go to stderr via console.error

export async function listResources() {
  // TODO: Implement real resources if needed (e.g., cached queries, presets)
  return { resources: [] };
}

export async function readResource(uri) {
  // TODO: Implement reading specific resource by uri
  console.error('[resources.read] Not implemented for uri:', uri);
  return {
    mimeType: 'text/plain',
    // Returning a stub content to keep server functional
    text: `Resource '${uri}' is not implemented yet.`,
  };
}
