use anyhow::Result;
use serde::Serialize;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use crate::registry::{RegistrySnapshot, SwapRegistry};

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    registry: RegistrySnapshot,
}

pub async fn start_health_server(
    addr: &str,
    registry: std::sync::Arc<tokio::sync::RwLock<SwapRegistry>>,
) -> Result<tokio::task::JoinHandle<()>> {
    let listener = TcpListener::bind(addr).await?;
    let handle = tokio::spawn(async move {
        loop {
            let (mut socket, _) = match listener.accept().await {
                Ok(value) => value,
                Err(_) => continue,
            };

            let mut buf = [0u8; 1024];
            let _ = socket.read(&mut buf).await;

            let snapshot = registry.read().await.snapshot();
            let body = serde_json::to_string(&HealthResponse {
                status: "ok",
                registry: snapshot,
            })
            .unwrap_or_else(|_| "{\"status\":\"error\"}".to_string());

            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                body.len(),
                body
            );

            let _ = socket.write_all(response.as_bytes()).await;
        }
    });

    Ok(handle)
}
