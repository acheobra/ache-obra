import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SuporteEmailPage extends StatelessWidget {
  const SuporteEmailPage({super.key});

  Future<void> _enviarEmail(BuildContext context) async {
    const String emailDestino = 'suporte@acheobra.com.br';

    // 1. Busca os dados do usuário logado no Supabase
    final user = Supabase.instance.client.auth.currentUser;

    // Tenta pegar o nome salvo nos metadados da conta; se não achar, usa 'Usuário'
    String nomeUsuario = user?.userMetadata?['nome'] ??
        user?.userMetadata?['full_name'] ??
        'Usuário';

    // Se por acaso o nome ainda vier vazio, ajustamos para um texto padrão
    if (nomeUsuario.trim().isEmpty) {
      nomeUsuario = 'Usuário';
    }

    // 2. Define o Assunto e o Corpo conforme solicitado
    final String assunto = 'Suporte - $nomeUsuario';
    const String corpo = 'Preciso de ajuda com...';

    // 3. Monta o link mailto manualmente usando Uri.encodeComponent
    // Isso Evita que o Android coloque os sinais de '+' no lugar dos espaços!
    final String mailtoUrl = 'mailto:$emailDestino'
        '?subject=${Uri.encodeComponent(assunto)}'
        '&body=${Uri.encodeComponent(corpo)}';

    final Uri emailUri = Uri.parse(mailtoUrl);

    try {
      // Tenta abrir o aplicativo de e-mail externo
      final bool disparou = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );

      if (!disparou) {
        throw 'Não foi possível abrir o app de e-mail diretamente.';
      }
    } catch (e) {
      debugPrint('Erro ao abrir e-mail: $e');

      // Copia o e-mail para a área de transferência como garantia
      await Clipboard.setData(const ClipboardData(text: emailDestino));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não encontramos um app de e-mail configurado. O e-mail suporte@acheobra.com.br foi copiado!',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text('Suporte e Atendimento',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.email_outlined,
              size: 80,
              color: Color(0xFFFF8C00),
            ),
            const SizedBox(height: 24),
            const Text(
              'Precisa de Ajuda?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Clique no botão abaixo para entrar em contato diretamente com a nossa equipe através do e-mail suporte@acheobra.com.br.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _enviarEmail(context),
              icon: const Icon(Icons.send, color: Colors.white),
              label: const Text(
                'Enviar E-mail para Suporte',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            const Text(
              'Prazo de resposta: Até 24 horas úteis.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
