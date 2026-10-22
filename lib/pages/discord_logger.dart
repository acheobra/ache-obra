import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DiscordLogger {
  // Cole aqui a URL do Webhook do seu servidor no Discord
  static const String _webhookUrl = 'SUA_WEBHOOK_URL_DO_DISCORD_AQUI';

  static Future<void> enviarErro({
    required String origem, // Ex: "Login" ou "Cadastro"
    required Object erro,
    String? email,
  }) async {
    if (_webhookUrl.isEmpty || _webhookUrl.contains('SUA_WEBHOOK_URL')) return;

    try {
      final payload = {
        "embeds": [
          {
            "title": "🚨 Falha Registrada - $origem",
            "color": 16711680, // Cor vermelha em decimal
            "fields": [
              {
                "name": "Email Tentado",
                "value":
                    email != null && email.isNotEmpty ? email : "Não informado",
                "inline": true
              },
              {"name": "Origem", "value": origem, "inline": true},
              {
                "name": "Detalhes do Erro",
                "value": "```$erro```",
                "inline": false
              }
            ],
            "timestamp": DateTime.now().toUtc().toIso8601String(),
          }
        ]
      };

      await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint("Erro ao enviar log para o Discord: $e");
    }
  }
}
