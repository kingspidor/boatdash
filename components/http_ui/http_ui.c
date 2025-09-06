#include <string.h>
#include "esp_log.h"
#include "esp_err.h"
#include "esp_http_server.h"
#include "http_ui.h"

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

static const char *TAG = "http_ui";
static httpd_handle_t s_server = NULL;

// Keep track of active WebSocket sessions
#define MAX_CLIENTS 8
static int ws_fds[MAX_CLIENTS] = {0};

/* ========== WebSocket Handler ========== */

static esp_err_t ws_handler(httpd_req_t *req) {
    if (req->method == HTTP_GET) {
        ESP_LOGI(TAG, "Handshake done, new WebSocket client");
        return ESP_OK;
    }

    httpd_ws_frame_t ws_pkt;
    memset(&ws_pkt, 0, sizeof(httpd_ws_frame_t));

    ws_pkt.type = HTTPD_WS_TYPE_TEXT;
    ws_pkt.payload = NULL;

    if (httpd_ws_recv_frame(req, &ws_pkt, 0) != ESP_OK) {
        ESP_LOGE(TAG, "Failed to get WS frame length");
        return ESP_FAIL;
    }

    ws_pkt.payload = malloc(ws_pkt.len + 1);
    if (!ws_pkt.payload) {
        return ESP_ERR_NO_MEM;
    }

    if (httpd_ws_recv_frame(req, &ws_pkt, ws_pkt.len) != ESP_OK) {
        ESP_LOGE(TAG, "Failed to get WS frame payload");
        free(ws_pkt.payload);
        return ESP_FAIL;
    }
    ws_pkt.payload[ws_pkt.len] = '\0';

    ESP_LOGI(TAG, "WS message received: %s", ws_pkt.payload);
    free(ws_pkt.payload);

    // Store client socket for broadcasting
    int fd = httpd_req_to_sockfd(req);
    bool already = false;
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (ws_fds[i] == fd) already = true;
    }
    if (!already) {
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (ws_fds[i] == 0) {
                ws_fds[i] = fd;
                ESP_LOGI(TAG, "Client %d added to broadcast list", fd);
                break;
            }
        }
    }

    return ESP_OK;
}

/* ========== Handlers ========== */

static esp_err_t static_get_handler(httpd_req_t *req) {
    const char *resp_str = "<html><body><h1>BoatDash UI</h1><p>Static page served!</p></body></html>";
    httpd_resp_send(req, resp_str, HTTPD_RESP_USE_STRLEN);
    return ESP_OK;
}

static esp_err_t relays_post_handler(httpd_req_t *req) {
    char buf[128];
    int ret, remaining = req->content_len;

    while (remaining > 0) {
        if ((ret = httpd_req_recv(req, buf, MIN(remaining, sizeof(buf)))) <= 0) {
            if (ret == HTTPD_SOCK_ERR_TIMEOUT) {
                continue; // retry
            }
            return ESP_FAIL;
        }
        remaining -= ret;
    }

    ESP_LOGI(TAG, "Relay POST received");
    httpd_resp_sendstr(req, "Relay command processed");
    return ESP_OK;
}

/* ========== Public API ========== */

void http_ui_start(void) {
    if (s_server != NULL) {
        ESP_LOGW(TAG, "HTTP server already running");
        return;
    }

    httpd_config_t config = HTTPD_DEFAULT_CONFIG();

    ESP_LOGI(TAG, "Starting HTTP server on port: %d", config.server_port);
    if (httpd_start(&s_server, &config) != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start HTTP server");
        return;
    }

    // Static files
    httpd_uri_t any_static = {
        .uri       = "/*",
        .method    = HTTP_GET,
        .handler   = static_get_handler,
        .user_ctx  = NULL
    };
    httpd_register_uri_handler(s_server, &any_static);

    // Relay API
    httpd_uri_t relays = {
        .uri       = "/api/relays",
        .method    = HTTP_POST,
        .handler   = relays_post_handler,
        .user_ctx  = NULL
    };
    httpd_register_uri_handler(s_server, &relays);

    // WebSocket endpoint
    httpd_uri_t ws = {
        .uri        = "/ws",
        .method     = HTTP_GET,
        .handler    = ws_handler,
        .user_ctx   = NULL,
        .is_websocket = true
    };
    httpd_register_uri_handler(s_server, &ws);

    ESP_LOGI(TAG, "HTTP/UI started with WebSocket support");
}

void http_ui_broadcast_json(const char* json, size_t len) {
    if (s_server == NULL) {
        ESP_LOGW(TAG, "Broadcast failed: server not running");
        return;
    }

    httpd_ws_frame_t ws_pkt;
    memset(&ws_pkt, 0, sizeof(httpd_ws_frame_t));

    ws_pkt.type = HTTPD_WS_TYPE_TEXT;
    ws_pkt.payload = (uint8_t*)json;
    ws_pkt.len = len;

    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (ws_fds[i] != 0) {
            int sock = ws_fds[i];
            esp_err_t ret = httpd_ws_send_frame_async(s_server, sock, &ws_pkt);
            if (ret != ESP_OK) {
                ESP_LOGW(TAG, "Failed to send WS frame to client %d: %s", sock, esp_err_to_name(ret));
                ws_fds[i] = 0; // remove dead client
            }
        }
    }
}

bool http_ui_is_request_from_ap(httpd_req_t* req) {
    // TODO: detect if client is from AP or STA interface
    return false;
}
