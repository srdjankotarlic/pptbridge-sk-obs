#include "../src/pptbridge_osc_server.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

extern "C" void blog(int, const char *, ...)
{
}

namespace {

std::mutex g_actions_mutex;
std::vector<pptbridge::OscAction> g_actions;

void collect_action(pptbridge::OscAction action)
{
  std::lock_guard<std::mutex> lock(g_actions_mutex);
  g_actions.push_back(action);
}

bool send_osc_address(uint16_t port, const std::string &address, bool terminate = true)
{
  int socket_fd = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socket_fd < 0) {
    return false;
  }

  sockaddr_in destination = {};
  destination.sin_family = AF_INET;
  destination.sin_port = htons(port);
  inet_pton(AF_INET, "127.0.0.1", &destination.sin_addr);

  std::vector<char> packet(address.begin(), address.end());
  if (terminate) {
    packet.push_back('\0');
    while (packet.size() % 4 != 0) {
      packet.push_back('\0');
    }
  }
  const ssize_t sent = sendto(
    socket_fd,
    packet.data(),
    packet.size(),
    0,
    reinterpret_cast<const sockaddr *>(&destination),
    sizeof(destination));
  close(socket_fd);
  return sent == static_cast<ssize_t>(packet.size());
}

}  // namespace

int main()
{
  constexpr uint16_t kPort = 57247;
  if (!pptbridge::StartOscServer(kPort, collect_action) || !pptbridge::OscServerRunning()) {
    std::fprintf(stderr, "OSC server did not start\n");
    return 1;
  }

  const std::vector<std::pair<std::string, pptbridge::OscAction>> commands = {
    { "/pptbridge/next", pptbridge::OscAction::Next },
    { "/PPTBRIDGE/PREVIOUS", pptbridge::OscAction::Previous },
    { "/pptbridge/prev", pptbridge::OscAction::Previous },
    { "/pptbridge/first", pptbridge::OscAction::First },
    { "/pptbridge/last", pptbridge::OscAction::Last },
    { "/pptbridge/black", pptbridge::OscAction::Black },
    { "/pptbridge/blank", pptbridge::OscAction::Black },
    { "/pptbridge/reload", pptbridge::OscAction::Reload },
  };

  for (const auto &[address, action] : commands) {
    (void)action;
    if (!send_osc_address(kPort, address)) {
      std::fprintf(stderr, "could not send %s\n", address.c_str());
      pptbridge::StopOscServer();
      return 1;
    }
  }
  send_osc_address(kPort, "/pptbridge/unknown");
  send_osc_address(kPort, "/pptbridge/next", false);

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  while (std::chrono::steady_clock::now() < deadline) {
    {
      std::lock_guard<std::mutex> lock(g_actions_mutex);
      if (g_actions.size() == commands.size()) {
        break;
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  pptbridge::StopOscServer();
  if (pptbridge::OscServerRunning()) {
    std::fprintf(stderr, "OSC server still reports running after stop\n");
    return 1;
  }

  std::lock_guard<std::mutex> lock(g_actions_mutex);
  if (g_actions.size() != commands.size()) {
    std::fprintf(stderr, "expected %zu actions, got %zu\n", commands.size(), g_actions.size());
    return 1;
  }
  for (std::size_t index = 0; index < commands.size(); ++index) {
    if (g_actions[index] != commands[index].second) {
      std::fprintf(stderr, "wrong action at index %zu\n", index);
      return 1;
    }
  }

  std::printf("osc control smoke ok: %zu commands, malformed/unknown ignored\n", g_actions.size());
  return 0;
}
