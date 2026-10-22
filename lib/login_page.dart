import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/feed_page.dart';
import '../main.dart';

class DiscordLogger {
  static const String _webhookUrl =
      'https://discord.com/api/webhooks/1539960415960834139/4eQduRq4xoQnP4lCwOUBXXVDxyUGL-wXmDvXNJr7x9Niy9JjHkHqXmAOXNei9rNP74rD';

  static Future<void> enviarErro({
    required String origem,
    required Object erro,
    String? email,
  }) async {
    if (_webhookUrl.isEmpty) return;

    try {
      final payload = {
        "embeds": [
          {
            "title": "🚨 Falha Registrada - $origem",
            "color": 16711680,
            "fields": [
              {
                "name": "E-mail Tentado",
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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  String? _validarSenha(String password) {
    if (password.length < 6 || password.length > 8) {
      return "A senha deve ter no mínimo 6 e no máximo 8 dígitos.";
    }

    if (!RegExp(r'^\d+$').hasMatch(password)) {
      return "A senha deve conter apenas números.";
    }

    bool repetido = true;
    for (int i = 1; i < password.length; i++) {
      if (password[i] != password[0]) {
        repetido = false;
        break;
      }
    }
    if (repetido) {
      return "A senha não pode ser formada por números repetidos.";
    }

    bool seqCrescente = true;
    bool seqDecrescente = true;
    for (int i = 1; i < password.length; i++) {
      int ant = int.parse(password[i - 1]);
      int atual = int.parse(password[i]);
      if (atual != ant + 1) seqCrescente = false;
      if (atual != ant - 1) seqDecrescente = false;
    }
    if (seqCrescente || seqDecrescente) {
      return "A senha não pode conter números sequenciais (ex: 123456).";
    }

    return null;
  }

  Future<void> _mostrarAlertaCredenciaisIncorretas() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF253c59),
        title: const Text('Atenção', style: TextStyle(color: Colors.white)),
        content: const Text(
          'E-mail não cadastrado ou senha incorreta. Verifique seus dados ou faça seu cadastro.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarContaBloqueada() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(
              color: Colors.redAccent,
              width: 1.2,
            ),
          ),
          title: const Column(
            children: [
              Icon(
                Icons.block_rounded,
                color: Colors.redAccent,
                size: 64,
              ),
              SizedBox(height: 14),
              Text(
                'CONTA BLOQUEADA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Sua conta foi bloqueada por descumprir as políticas da plataforma Ache Obra.\n\n'
            'Para mais informações ou esclarecimentos, entre em contato pelo e-mail:\n'
            'suporte@acheobra.com.br',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'SAIR',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reativarConta(String userId) async {
    try {
      await Supabase.instance.client.from('tab_usuarios').update({
        'usuario_status': 'ativo',
        'exclusao_solicitada_em': null,
      }).eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Conta reativada com sucesso! Faça login novamente."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      DiscordLogger.enviarErro(
        origem: 'Reativação de Conta',
        erro: e,
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao reativar conta: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha e-mail e senha.")),
      );
      return;
    }

    final erroSenha = _validarSenha(password);
    if (erroSenha != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroSenha), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw "Erro ao autenticar usuário.";

      final dadosUsuario = await Supabase.instance.client
          .from('tab_usuarios')
          .select('id, usuario_status')
          .eq('id', user.id)
          .maybeSingle();

      if (dadosUsuario == null) {
        await Supabase.instance.client.auth.signOut();

        DiscordLogger.enviarErro(
          origem: 'Login - Usuário sem registro na tab_usuarios',
          erro:
              'Login no Auth aprovado, porém registro inexistente na tab_usuarios',
          email: email,
        );

        if (!mounted) return;
        setState(() => _isLoading = false);
        await _mostrarAlertaCredenciaisIncorretas();
        return;
      }

      final status = (dadosUsuario['usuario_status'] ?? 'ativo')
          .toString()
          .trim()
          .toLowerCase();

      // BLOQUEADO: não permite chegar ao Feed. A sessão é encerrada antes
      // de exibir a mesma orientação usada no controle central do main.dart.
      if (status == 'bloqueado') {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) return;
        setState(() => _isLoading = false);

        await _mostrarContaBloqueada();
        return;
      }

      // INATIVO: mantém a rotina já existente de reativação voluntária.
      if (status == 'inativo') {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);

        bool? confirmarReativacao = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF253c59),
            title: const Text(
              'Conta Inativa',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Sua conta está inativa devido a uma solicitação de exclusão. Deseja reativar?',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Não',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Sim',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ],
          ),
        );

        if (confirmarReativacao == true) {
          await _reativarConta(user.id);
        }
        return;
      }

      // EXCLUÍDO: também não permite acesso. Não reutilizamos a rotina de
      // reativação automática de conta inativa.
      if (status == 'excluido' || status == 'excluído') {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) return;
        setState(() => _isLoading = false);

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF101B2B),
            title: const Text(
              'CONTA INDISPONÍVEL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Este cadastro está marcado como excluído e não possui acesso ao aplicativo.\n\n'
              'Para mais informações, entre em contato pelo e-mail:\n'
              'suporte@acheobra.com.br',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'SAIR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }

      // Somente depois da validação do status o usuário é enviado ao Feed.
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const FeedPage()),
      );
    } on AuthException catch (_) {
      // Erros de autenticação de credenciais (e-mail ou senha incorretos)
      // apenas alertam o usuário na interface e NÃO são enviados para o Discord.
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _mostrarAlertaCredenciaisIncorretas();
    } catch (e) {
      // Apenas exceções técnicas e erros inesperados do sistema são logados no Discord
      DiscordLogger.enviarErro(
        origem: 'Login - Erro Inesperado',
        erro: e,
        email: email,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro inesperado: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white24,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2C42),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Login", style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Image.asset(
                'assets/images/login_ache_obra.png',
                width: 110,
                height: 110,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.login,
                    color: Colors.orange,
                    size: 80,
                  );
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("E-mail"),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Senha (6 a 8 números)").copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white70),
                    onPressed: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();

                          mostrarDialogoEsqueciSenhaGlobal(
                            context,
                            _emailController.text.trim(),
                          );
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                  ),
                  child: const Text(
                    "Esqueci minha senha",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.orange,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.black))
                      : const Text("ENTRAR",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
