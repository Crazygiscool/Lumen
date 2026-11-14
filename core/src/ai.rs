//! Local AI integration via Ollama.
//!
//! Privacy model: nothing leaves the user's machine. The Ollama server runs
//! locally (http://localhost:11434 by default), and Lumen only sends the
//! notes the user explicitly selects as context.

use std::time::Duration;

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};

/// The Ollama HTTP client.
///
/// All requests go to `localhost:11434` by default. Nothing is ever sent to
/// an external API unless the user configures a different URL (which they
/// shouldn't, for privacy).
pub struct OllamaClient {
    base_url: String,
    client: Client,
}

impl OllamaClient {
    /// Create a new Ollama client for the given base URL.
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            client: Client::builder()
                .timeout(Duration::from_secs(300))
                .build()
                .expect("failed to create HTTP client"),
        }
    }

    /// Default base URL (localhost).
    pub fn default() -> Self {
        Self::new("http://localhost:11434")
    }

    /// List installed models.
    pub fn list_models(&self) -> crate::Result<Vec<ModelInfo>> {
        let url = format!("{}/api/tags", self.base_url);
        let resp: ListModelsResponse = self.client.get(&url).send().map_err(|e| {
            format!("failed to list models: {e}")
        })?.json().map_err(|e| format!("failed to parse model list: {e}"))?;
        Ok(resp.models)
    }

    /// Chat with a model, optionally streaming a callback for each token.
    pub fn chat(
        &self,
        model: &str,
        messages: Vec<Message>,
        stream: bool,
    ) -> crate::Result<ChatResponse> {
        let url = format!("{}/api/chat", self.base_url);
        let req = ChatRequest {
            model: model.to_string(),
            messages,
            stream,
        };
        let resp: ChatResponse = self.client.post(&url).json(&req).send().map_err(|e| {
            format!("failed to send chat request: {e}")
        })?.json().map_err(|e| format!("failed to parse chat response: {e}"))?;
        Ok(resp)
    }

    /// Generate embeddings for texts.
    pub fn embeddings(
        &self,
        model: &str,
        texts: &[String],
    ) -> crate::Result<Vec<Vec<f32>>> {
        let url = format!("{}/api/embeddings", self.base_url);
        let mut results = Vec::with_capacity(texts.len());
        for text in texts {
            let req = EmbeddingsRequest {
                model: model.to_string(),
                prompt: text.clone(),
            };
            let resp: EmbeddingsResponse = self.client.post(&url).json(&req).send().map_err(|e| {
                format!("failed to send embeddings request: {e}")
            })?.json().map_err(|e| format!("failed to parse embeddings response: {e}"))?;
            results.push(resp.embedding);
        }
        Ok(results)
    }
}

/// A model installed on the Ollama server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub name: String,
    pub modified_at: String,
    pub size: u64,
    pub digest: String,
}

/// The list-models response from Ollama.
#[derive(Debug, Deserialize)]
struct ListModelsResponse {
    pub models: Vec<ModelInfo>,
}

/// A chat message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

impl Message {
    /// A system message.
    pub fn system(content: &str) -> Self {
        Self {
            role: "system".to_string(),
            content: content.to_string(),
        }
    }

    /// A user message.
    pub fn user(content: &str) -> Self {
        Self {
            role: "user".to_string(),
            content: content.to_string(),
        }
    }

    /// An assistant message.
    pub fn assistant(content: &str) -> Self {
        Self {
            role: "assistant".to_string(),
            content: content.to_string(),
        }
    }
}

/// The chat request sent to Ollama.
#[derive(Debug, Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    stream: bool,
}

/// The chat response from Ollama.
#[derive(Debug, Deserialize)]
pub struct ChatResponse {
    pub model: String,
    pub created_at: String,
    pub message: Message,
    pub done: bool,
}

/// The embeddings request sent to Ollama.
#[derive(Debug, Serialize)]
struct EmbeddingsRequest {
    model: String,
    prompt: String,
}

/// The embeddings response from Ollama.
#[derive(Debug, Deserialize)]
struct EmbeddingsResponse {
    pub embedding: Vec<f32>,
}

/// Context retrieved for a RAG query.
#[derive(Debug, Clone)]
pub struct NoteContext {
    pub path: String,
    pub title: String,
    pub body: String,
    pub score: f32,
}

/// Retrieve relevant notes for a RAG query.
///
/// Uses Tantivy for candidate retrieval, then optionally re-ranks by
/// embedding similarity if an embedding model is configured.
pub fn retrieve_context(
    ollama: &OllamaClient,
    embedding_model: Option<&str>,
    query: &str,
    store: &str,
    k: usize,
) -> crate::Result<Vec<NoteContext>> {
    // Get candidate notes from Tantivy.
    let hits = crate::search::search_entries(store, query, k * 3)?;
    let mut contexts: Vec<NoteContext> = Vec::new();
    for hit in hits {
        let body = crate::vault::read_text(&hit.path, store).unwrap_or_default();
        let title = hit.title.clone();
        contexts.push(NoteContext {
            path: hit.path,
            title,
            body,
            score: hit.score,
        });
    }

    // Re-rank by embedding similarity if an embedding model is available.
    if let Some(model) = embedding_model {
        let query_embedding = ollama.embeddings(model, &[query.to_string()])?;
        let query_vec = &query_embedding[0];

        let note_texts: Vec<String> = contexts
            .iter()
            .map(|c| format!("{} {}", c.title, c.body))
            .collect();
        let note_embeddings = ollama.embeddings(model, &note_texts)?;

        for (i, ctx) in contexts.iter_mut().enumerate() {
            let note_vec = &note_embeddings[i];
            ctx.score = cosine_similarity(query_vec, note_vec);
        }

        contexts.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    }

    contexts.truncate(k);
    Ok(contexts)
}

/// Cosine similarity between two vectors.
fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm_a == 0.0 || norm_b == 0.0 {
        0.0
    } else {
        dot / (norm_a * norm_b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        assert!((cosine_similarity(&a, &b) - 1.0).abs() < 1e-6);

        let c = vec![0.0, 1.0, 0.0];
        assert!((cosine_similarity(&a, &c) - 0.0).abs() < 1e-6);

        let d = vec![-1.0, 0.0, 0.0];
        assert!((cosine_similarity(&a, &d) - -1.0).abs() < 1e-6);
    }

    #[test]
    fn test_message_constructors() {
        let sys = Message::system("You are helpful.");
        assert_eq!(sys.role, "system");
        assert_eq!(sys.content, "You are helpful.");

        let user = Message::user("Hello");
        assert_eq!(user.role, "user");
        assert_eq!(user.content, "Hello");

        let assistant = Message::assistant("Hi there");
        assert_eq!(assistant.role, "assistant");
        assert_eq!(assistant.content, "Hi there");
    }
}
