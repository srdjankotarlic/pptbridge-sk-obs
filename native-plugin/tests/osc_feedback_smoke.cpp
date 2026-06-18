#include "../src/pptbridge_osc_server.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdarg>
#include <cstdio>
#include <set>
#include <string>

extern "C" void blog(int, const char *, ...)
{
}

namespace {

std::string osc_address(const char *buffer, ssize_t size)
{
  if (size <= 0 || buffer[0] != '/') {
    return {};
  }
  ssize_t offset = 0;
  while (offset < size && buffer[offset] != '\0') {
    ++offset;
  }
  return std::string(buffer, static_cast<std::size_t>(offset));
}

}  // namespace

int main()
{
  int socket_fd = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socket_fd < 0) {
    std::perror("socket");
    return 1;
  }

  sockaddr_in bind_address = {};
  bind_address.sin_family = AF_INET;
  bind_address.sin_port = 0;
  if (inet_pton(AF_INET, "127.0.0.1", &bind_address.sin_addr) != 1) {
    std::fprintf(stderr, "inet_pton failed\n");
    close(socket_fd);
    return 1;
  }
  if (bind(socket_fd, reinterpret_cast<sockaddr *>(&bind_address), sizeof(bind_address)) != 0) {
    std::perror("bind");
    close(socket_fd);
    return 1;
  }

  sockaddr_in actual_address = {};
  socklen_t actual_size = sizeof(actual_address);
  if (getsockname(socket_fd, reinterpret_cast<sockaddr *>(&actual_address), &actual_size) != 0) {
    std::perror("getsockname");
    close(socket_fd);
    return 1;
  }
  const uint16_t port = ntohs(actual_address.sin_port);

  pptbridge::PresentationStatus status;
  status.current_slide = 3;
  status.total_slides = 12;
  status.current_title = "Current";
  status.next_title = "Next";
  status.deck_name = "deck.pdf";
  status.deck_path = "/tmp/deck.pdf";
  status.source_name = "PPTBridge Main";
  status.error = "none";
  status.timer_seconds = 42;
  status.live_ready = true;
  status.loading = false;
  status.loaded = true;
  status.black_screen = false;
  status.current_cue_checked = true;
  status.next_cue_checked = false;
  status.checked_count = 5;

  if (!pptbridge::SendOscStatusFeedback("127.0.0.1", port, status)) {
    std::fprintf(stderr, "SendOscStatusFeedback returned false\n");
    close(socket_fd);
    return 1;
  }

  const std::set<std::string> expected = {
    "/pptbridge/status/current",
    "/pptbridge/status/total",
    "/pptbridge/status/title",
    "/pptbridge/status/next_title",
    "/pptbridge/status/deck_name",
    "/pptbridge/status/deck_path",
    "/pptbridge/status/source_name",
    "/pptbridge/status/error",
    "/pptbridge/status/timer",
    "/pptbridge/status/live",
    "/pptbridge/status/loading",
    "/pptbridge/status/loaded",
    "/pptbridge/status/black",
    "/pptbridge/status/cue_current_checked",
    "/pptbridge/status/cue_next_checked",
    "/pptbridge/status/cue_checked_count",
  };

  std::set<std::string> received;
  char buffer[1024] = {};
  for (int attempt = 0; attempt < 32 && received.size() < expected.size(); ++attempt) {
    fd_set read_set;
    FD_ZERO(&read_set);
    FD_SET(socket_fd, &read_set);
    timeval timeout = {};
    timeout.tv_sec = 0;
    timeout.tv_usec = 250000;
    const int ready = select(socket_fd + 1, &read_set, nullptr, nullptr, &timeout);
    if (ready <= 0) {
      continue;
    }
    const ssize_t size = recv(socket_fd, buffer, sizeof(buffer), 0);
    const auto address = osc_address(buffer, size);
    if (!address.empty()) {
      received.insert(address);
    }
  }

  close(socket_fd);

  for (const auto &address : expected) {
    if (received.find(address) == received.end()) {
      std::fprintf(stderr, "missing OSC status address: %s\n", address.c_str());
      return 1;
    }
  }

  std::printf("osc feedback smoke ok: %zu messages\n", received.size());
  return 0;
}
