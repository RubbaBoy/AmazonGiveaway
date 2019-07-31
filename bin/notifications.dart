import 'dart:io';

class Notifications {
  bool ENABLED = false;

  Socket socket;

  Future<void> connect() async {
    if (ENABLED) socket = await Socket.connect('localhost', 15879);
  }

  void sendNotification(String title, String body) {
    if (ENABLED) socket.writeln('$title|$body');
  }
}

