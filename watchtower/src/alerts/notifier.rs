use anyhow::Result;
use reqwest::Client;
use serde_json::json;
use tracing::{info, error};

use crate::types::{Alert, AlertLevel};

/// Alert notifier supporting multiple channels
pub struct Notifier {
    client: Client,
    discord_webhook: Option<String>,
    telegram_bot_token: Option<String>,
    telegram_chat_id: Option<String>,
}

impl Notifier {
    pub fn new(
        discord_webhook: Option<String>,
        telegram_bot_token: Option<String>,
        telegram_chat_id: Option<String>,
    ) -> Self {
        Self {
            client: Client::new(),
            discord_webhook,
            telegram_bot_token,
            telegram_chat_id,
        }
    }

    pub async fn send_alert(&self, alert: &Alert) -> Result<()> {
        info!("Sending alert: {} - {}", alert.title, alert.message);
        
        // Send to Discord
        if let Some(ref webhook) = self.discord_webhook {
            self.send_discord(webhook, alert).await?;
        }
        
        // Send to Telegram
        if let (Some(ref token), Some(ref chat_id)) = 
            (&self.telegram_bot_token, &self.telegram_chat_id) 
        {
            self.send_telegram(token, chat_id, alert).await?;
        }
        
        Ok(())
    }

    async fn send_discord(&self, webhook: &str, alert: &Alert) -> Result<()> {
        let color = match alert.level {
            AlertLevel::Info => 0x00FF00,     // Green
            AlertLevel::Warning => 0xFFFF00,  // Yellow
            AlertLevel::Critical => 0xFF0000, // Red
        };
        let payload = json!({
            "embeds": [{
                "title": alert.title,
                "description": alert.message,
                "color": color,
                "fields": [{
                    "name": "Contract",
                    "value": format!("0x{:x}", alert.contract_address),
                    "inline": true
                }],
                "timestamp": chrono::Utc::now().to_rfc3339()
            }]
        });
        self.client
            .post(webhook)
            .json(&payload)
            .send()
            .await?;
        
        Ok(())
    }

    async fn send_telegram(
        &self,
        token: &str,
        chat_id: &str,
        alert: &Alert,
    ) -> Result<()> {
        let emoji = match alert.level {
            AlertLevel::Info => "ℹ️",
            AlertLevel::Warning => "⚠️",
            AlertLevel::Critical => "🚨",
        };
        let text = format!(
            "{} *{}*\n\n{}\n\nContract: `0x{:x}`",
            emoji,
            alert.title,
            alert.message,
            alert.contract_address
        );
        let url = format!(
            "https://api.telegram.org/bot{}/sendMessage",
            token
        );
        self.client
            .post(&url)
            .json(&json!({
                "chat_id": chat_id,
                "text": text,
                "parse_mode": "Markdown"
            }))
            .send()
            .await?;
        
        Ok(())
    }
}

