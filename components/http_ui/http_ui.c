#include "http_ui.h"
s_relays.nav?"true":"false", s_relays.all?"true":"false", s_relays.spot?"true":"false");
httpd_resp_set_type(req, "application/json");
return httpd_resp_send(req, out, n);
}


// --- WebSocket
#if CONFIG_HTTPD_WS_SUPPORT
static esp_err_t ws_handler(httpd_req_t* req){
if(req->method == HTTP_GET) return ESP_OK; // handshake handled by core
httpd_ws_frame_t f = {0};
f.type = HTTPD_WS_TYPE_TEXT; // ignore payloads from client for now
return httpd_ws_recv_frame(req, &f, 0);
}
#endif


// Broadcast to all /ws clients
void http_ui_broadcast_json(const char* json, size_t len){
#if CONFIG_HTTPD_WS_SUPPORT
if(!s_server) return;
size_t max = 0; httpd_get_client_list(s_server, &max, NULL);
if(max==0) return;
int *fdset = calloc(max, sizeof(int));
if(!fdset) return;
if(httpd_get_client_list(s_server, &max, fdset)==ESP_OK){
for(size_t i=0;i<max;i++){
int fd = fdset[i];
if(httpd_ws_get_fd_info(s_server, fd) == HTTPD_WS_CLIENT_WEBSOCKET){
httpd_ws_frame_t pkt = { .type = HTTPD_WS_TYPE_TEXT, .payload = (uint8_t*)json, .len = len };
if(httpd_ws_send_frame_async(s_server, fd, &pkt) != ESP_OK){ /* ignore errors */ }
}
}
}
free(fdset);
#else
(void)json; (void)len;
#endif
}


bool http_ui_is_request_from_ap(httpd_req_t* req){
int fd = httpd_req_to_sockfd(req);
struct sockaddr_in peer; socklen_t l=sizeof(peer);
if(getpeername(fd,(struct sockaddr*)&peer,&l)!=0) return false;
uint32_t ip = ntohl(peer.sin_addr.s_addr);
return ( (ip & 0xFFFFFF00u) == 0xC0A80400u ); // 192.168.4.0/24
}


void http_ui_start(void){
httpd_config_t c = HTTPD_DEFAULT_CONFIG();
ESP_ERROR_CHECK(httpd_start(&s_server,&c));

// Static files from LittleFS
httpd_uri_t any_static = { .uri = "/*", .method = HTTP_GET, .handler = static_get_handler, .user_ctx = NULL };
httpd_register_uri_handler(s_server, &any_static);

// Root (optional explicit)
httpd_uri_t root = { .uri = "/", .method = HTTP_GET, .handler = static_get_handler, .user_ctx = NULL };
httpd_register_uri_handler(s_server, &root);


// Relays API
httpd_uri_t relays = { .uri = "/api/relays", .method = HTTP_POST, .handler = relays_post_handler, .user_ctx = NULL };
httpd_register_uri_handler(s_server, &relays);


#if CONFIG_HTTPD_WS_SUPPORT
// WebSocket endpoint
httpd_uri_t ws = { .uri = "/ws", .method = HTTP_GET, .handler = ws_handler, .user_ctx = NULL };
ws.is_websocket = true;
httpd_register_uri_handler(s_server, &ws);
#endif




ESP_LOGI(TAG, "HTTP/UI started");
}