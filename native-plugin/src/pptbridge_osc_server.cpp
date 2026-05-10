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

}  // namespace pptbridge
