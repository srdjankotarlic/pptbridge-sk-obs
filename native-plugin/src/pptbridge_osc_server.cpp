#include "pptbridge_osc_server.hpp"

#include <obs-module.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cstring>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace pptbridge {
namespace {

#ifdef _WIN32
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;

void close_socket(SocketHandle socket)
{
  closesocket(socket);
}
#else
using SocketHandle = int;
constexpr SocketHandle kInvalidSocket = -1;

void close_socket(SocketHandle socket)
{
  close(socket);
}
#endif

std::optional<OscAction> parse_osc_action(const char *data, size_t size)
{
  if (!data || size < 2 || data[0] != '/') {
    return std::nullopt;
  }

  size_t address_size = 0;
  while (address_size < size && data[address_size] != '\0') {
    ++address_size;
  }
  if (address_size == size) {
    return std::nullopt;
  }

  std::string address(data, address_size);
  std::transform(address.begin(), address.end(), address.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });

  if (address == "/pptbridge/next") {
    return OscAction::Next;
  }
  if (address == "/pptbridge/previous" || address == "/pptbridge/prev") {
    return OscAction::Previous;
  }
  if (address == "/pptbridge/first") {
    return OscAction::First;
  }
  if (address == "/pptbridge/last") {
    return OscAction::Last;
  }
  if (address == "/pptbridge/black" || address == "/pptbridge/blank") {
    return OscAction::Black;
  }
  if (address == "/pptbridge/reload") {
    return OscAction::Reload;
  }

  return std::nullopt;
}

void append_osc_string(std::vector<uint8_t> &packet, const std::string &value)
{
  packet.insert(packet.end(), value.begin(), value.end());
  packet.push_back('\0');
  while (packet.size() % 4 != 0) {
    packet.push_back('\0');
  }
}

void append_osc_int(std::vector<uint8_t> &packet, int32_t value)
{
  const uint32_t network_value = htonl(static_cast<uint32_t>(value));
  const auto *bytes = reinterpret_cast<const uint8_t *>(&network_value);
  packet.insert(packet.end(), bytes, bytes + sizeof(network_value));
}

std::vector<uint8_t> make_osc_int_packet(const std::string &address, int32_t value)
{
  std::vector<uint8_t> packet;
  append_osc_string(packet, address);
  append_osc_string(packet, ",i");
  append_osc_int(packet, value);
  return packet;
}

std::vector<uint8_t> make_osc_string_packet(const std::string &address, const std::string &value)
{
  std::vector<uint8_t> packet;
  append_osc_string(packet, address);
  append_osc_string(packet, ",s");
  append_osc_string(packet, value);
  return packet;
}

bool send_udp_packet(SocketHandle socket, const sockaddr_in &address, const std::vector<uint8_t> &packet)
{
  if (packet.empty()) {
    return false;
  }
#ifdef _WIN32
  const int sent = sendto(
    socket,
    reinterpret_cast<const char *>(packet.data()),
    static_cast<int>(packet.size()),
    0,
    reinterpret_cast<const sockaddr *>(&address),
    sizeof(address));
  return sent == static_cast<int>(packet.size());
#else
  const ssize_t sent = sendto(
    socket,
    packet.data(),
    packet.size(),
    0,
    reinterpret_cast<const sockaddr *>(&address),
    sizeof(address));
  return sent == static_cast<ssize_t>(packet.size());
#endif
}

class OscServer {
public:
  bool Start(uint16_t port, OscActionCallback callback)
  {
    Stop();

    if (!callback) {
      return false;
    }

#ifdef _WIN32
    WSADATA wsa_data = {};
    if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
      blog(LOG_WARNING, "[PPTBridge SK] OSC: WSAStartup failed");
      return false;
    }
    wsa_started_ = true;
#endif

    SocketHandle socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socket == kInvalidSocket) {
      blog(LOG_WARNING, "[PPTBridge SK] OSC: could not create UDP socket");
      CleanupPlatform();
      return false;
    }

    int reuse = 1;
    setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char *>(&reuse), sizeof(reuse));
#ifdef _WIN32
    DWORD timeout_ms = 250;
    setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeout_ms), sizeof(timeout_ms));
#else
    timeval timeout = {};
    timeout.tv_usec = 250000;
    setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif

    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    if (inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) != 1) {
      close_socket(socket);
      CleanupPlatform();
      return false;
    }

    if (bind(socket, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
      blog(LOG_WARNING, "[PPTBridge SK] OSC: could not bind 127.0.0.1:%u", static_cast<unsigned>(port));
      close_socket(socket);
      CleanupPlatform();
      return false;
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      socket_ = socket;
      callback_ = callback;
      running_ = true;
    }

    thread_ = std::thread([this, socket, port]() {
      Run(socket, port);
    });

    blog(LOG_INFO, "[PPTBridge SK] OSC: listening on 127.0.0.1:%u", static_cast<unsigned>(port));
    return true;
  }

  void Stop()
  {
    SocketHandle socket = kInvalidSocket;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = false;
      socket = socket_;
      socket_ = kInvalidSocket;
      callback_ = nullptr;
    }

    if (socket != kInvalidSocket) {
      close_socket(socket);
    }

    if (thread_.joinable()) {
      thread_.join();
    }

    CleanupPlatform();
  }

  bool Running() const
  {
    return running_;
  }

private:
  void Run(SocketHandle socket, uint16_t port)
  {
    std::array<char, 1024> buffer = {};

    while (running_) {
      sockaddr_in sender = {};
#ifdef _WIN32
      int sender_size = sizeof(sender);
      const int received = recvfrom(
        socket,
        buffer.data(),
        static_cast<int>(buffer.size()),
        0,
        reinterpret_cast<sockaddr *>(&sender),
        &sender_size);
#else
      socklen_t sender_size = sizeof(sender);
      const ssize_t received = recvfrom(
        socket,
        buffer.data(),
        buffer.size(),
        0,
        reinterpret_cast<sockaddr *>(&sender),
        &sender_size);
#endif

      if (!running_) {
        break;
      }
      if (received <= 0) {
        continue;
      }

      const auto action = parse_osc_action(buffer.data(), static_cast<size_t>(received));
      if (!action) {
        continue;
      }

      OscActionCallback callback = nullptr;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        callback = callback_;
      }
      if (callback) {
        callback(*action);
      }
    }

    blog(LOG_INFO, "[PPTBridge SK] OSC: stopped listening on 127.0.0.1:%u", static_cast<unsigned>(port));
  }

  void CleanupPlatform()
  {
#ifdef _WIN32
    if (wsa_started_) {
      WSACleanup();
      wsa_started_ = false;
    }
#endif
  }

  mutable std::mutex mutex_;
  std::atomic<bool> running_ = false;
  SocketHandle socket_ = kInvalidSocket;
  OscActionCallback callback_ = nullptr;
  std::thread thread_;
#ifdef _WIN32
  bool wsa_started_ = false;
#endif
};

OscServer g_server;

}  // namespace

bool StartOscServer(uint16_t port, OscActionCallback callback)
{
  return g_server.Start(port, callback);
}

void StopOscServer()
{
  g_server.Stop();
}

bool OscServerRunning()
{
  return g_server.Running();
}

bool SendOscStatusFeedback(const std::string &host, uint16_t port, const PresentationStatus &status)
{
  if (host.empty() || port == 0) {
    return false;
  }

#ifdef _WIN32
  WSADATA wsa_data = {};
  const bool wsa_started = WSAStartup(MAKEWORD(2, 2), &wsa_data) == 0;
  if (!wsa_started) {
    blog(LOG_WARNING, "[PPTBridge SK] OSC feedback: WSAStartup failed");
    return false;
  }
#endif

  SocketHandle socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socket == kInvalidSocket) {
    blog(LOG_WARNING, "[PPTBridge SK] OSC feedback: could not create UDP socket");
#ifdef _WIN32
    WSACleanup();
#endif
    return false;
  }

  sockaddr_in address = {};
  address.sin_family = AF_INET;
  address.sin_port = htons(port);
  if (inet_pton(AF_INET, host.c_str(), &address.sin_addr) != 1) {
    blog(LOG_WARNING, "[PPTBridge SK] OSC feedback: invalid host '%s'", host.c_str());
    close_socket(socket);
#ifdef _WIN32
    WSACleanup();
#endif
    return false;
  }

  bool ok = true;
  ok = send_udp_packet(socket, address, make_osc_int_packet("/pptbridge/status/current", static_cast<int32_t>(status.current_slide))) && ok;
  ok = send_udp_packet(socket, address, make_osc_int_packet("/pptbridge/status/total", static_cast<int32_t>(status.total_slides))) && ok;
  ok = send_udp_packet(socket, address, make_osc_string_packet("/pptbridge/status/title", status.current_title)) && ok;
  ok = send_udp_packet(socket, address, make_osc_string_packet("/pptbridge/status/next_title", status.next_title)) && ok;
  ok = send_udp_packet(socket, address, make_osc_int_packet("/pptbridge/status/timer", static_cast<int32_t>(status.timer_seconds))) && ok;
  ok = send_udp_packet(socket, address, make_osc_int_packet("/pptbridge/status/live", status.live_ready ? 1 : 0)) && ok;
  ok = send_udp_packet(socket, address, make_osc_int_packet("/pptbridge/status/black", status.black_screen ? 1 : 0)) && ok;

  close_socket(socket);
#ifdef _WIN32
  WSACleanup();
#endif
  return ok;
}

}  // namespace pptbridge
