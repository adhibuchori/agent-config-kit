//! Starts the service: configuration, the startup checks, the pool, and a server that drains in
//! bounded time on SIGTERM or Ctrl-C. Wiring only: scripts/check/coverage-exempt.txt leaves this
//! file out of coverage, and everything it calls is tested in the library.

use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use service::{AppState, Config, app, check_problem_type_base, pool};
use tokio::net::TcpListener;
use tokio::sync::Notify;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(EnvFilter::from_default_env())
        .init();
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            tracing::error!(%error, "service stopped");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::from_env()?;
    check_problem_type_base(config.production)?;
    let listener = TcpListener::bind(config.listen).await?;
    let grace = config.shutdown_grace;
    let state = AppState {
        pool: pool(&config)?,
        config: Arc::new(config),
    };
    let stopping = Arc::new(Notify::new());
    let server =
        axum::serve(listener, app(state)).with_graceful_shutdown(signal(Arc::clone(&stopping)));
    tokio::select! {
        result = server.into_future() => result?,
        () = deadline(stopping, grace) => tracing::warn!("requests still ran after the shutdown grace"),
    }
    Ok(())
}

/// Resolves on Ctrl-C or SIGTERM, and starts the shutdown grace.
async fn signal(stopping: Arc<Notify>) {
    let interrupt = async {
        if tokio::signal::ctrl_c().await.is_err() {
            std::future::pending::<()>().await;
        }
    };
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut stream) => drop(stream.recv().await),
            Err(_unavailable) => std::future::pending::<()>().await,
        }
    };
    tokio::select! {
        () = interrupt => {},
        () = terminate => {},
    }
    stopping.notify_one();
}

/// Resolves once the grace has run out after a shutdown began.
async fn deadline(stopping: Arc<Notify>, grace: Duration) {
    stopping.notified().await;
    tokio::time::sleep(grace).await;
}
