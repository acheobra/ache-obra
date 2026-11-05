import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'configuracoes_page.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  final SupabaseClient _supabase = Supabase.instance.client;

  bool _carregando = false;
  bool _ocultarSenha = true;

  Future<void> _fazerLoginAdmin() async {
    if (_carregando) return;

    final String email = _emailController.text.trim().toLowerCase();

    // Não usamos trim() na senha porque espaços podem fazer parte dela.
    final String senha = _senhaController.text;

    if (email.isEmpty) {
      _mostrarMensagem(
        'Informe o e-mail do administrador.',
        Colors.orange,
      );
      return;
    }

    if (senha.isEmpty) {
      _mostrarMensagem(
        'Informe a senha.',
        Colors.orange,
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _carregando = true;
    });

    try {
      // ================================================================
      // 1. AUTENTICA O ADMINISTRADOR NO SUPABASE AUTH
      // ================================================================
      final AuthResponse response = await _supabase.auth.signInWithPassword(
        email: email,
        password: senha,
      );

      final User? user = response.user;

      if (user == null) {
        throw Exception(
          'O Supabase não retornou um usuário autenticado.',
        );
      }

      debugPrint('=================================================');
      debugPrint('[ADMIN LOGIN] Login no Supabase Auth realizado.');
      debugPrint('[ADMIN LOGIN] auth.uid = ${user.id}');
      debugPrint('[ADMIN LOGIN] auth.email = ${user.email}');
      debugPrint(
        '[ADMIN LOGIN] session existe = ${response.session != null}',
      );
      debugPrint('=================================================');

      // ================================================================
      // 2. CONFIRMA QUE A SESSÃO REALMENTE FICOU ATIVA
      // ================================================================
      final User? usuarioSessao = _supabase.auth.currentUser;

      final Session? sessao = _supabase.auth.currentSession;

      if (usuarioSessao == null || sessao == null) {
        await _supabase.auth.signOut();

        throw Exception(
          'A autenticação ocorreu, mas a sessão do Supabase '
          'não permaneceu ativa.',
        );
      }

      // ================================================================
      // 3. VERIFICA SE O USUÁRIO ESTÁ CADASTRADO COMO ADMIN
      //
      // Primeiro pelo E-MAIL.
      //
      // Isso evita depender obrigatoriamente de:
      // auth.users.id == tab_admin_users.id
      // ================================================================
      Map<String, dynamic>? adminEncontrado;

      try {
        final dynamic adminPorEmail = await _supabase
            .from('tab_admin_users')
            .select('*')
            .ilike('email', email)
            .maybeSingle();

        if (adminPorEmail != null) {
          adminEncontrado = Map<String, dynamic>.from(adminPorEmail);
        }
      } catch (e) {
        debugPrint(
          '[ADMIN LOGIN] Não foi possível validar admin por e-mail: $e',
        );
      }

      // ================================================================
      // 4. FALLBACK PELO ID
      //
      // Mantemos compatibilidade caso sua tab_admin_users utilize
      // exatamente o UUID do Supabase Auth.
      // ================================================================
      if (adminEncontrado == null) {
        try {
          final dynamic adminPorId = await _supabase
              .from('tab_admin_users')
              .select('*')
              .eq('id', user.id)
              .maybeSingle();

          if (adminPorId != null) {
            adminEncontrado = Map<String, dynamic>.from(adminPorId);
          }
        } catch (e) {
          debugPrint(
            '[ADMIN LOGIN] Não foi possível validar admin por ID: $e',
          );
        }
      }

      // ================================================================
      // 5. SE NÃO ESTIVER NA TABELA DE ADMINS, ENCERRA A SESSÃO
      // ================================================================
      if (adminEncontrado == null) {
        debugPrint(
          '[ADMIN LOGIN] Usuário autenticado, mas não encontrado '
          'em tab_admin_users.',
        );

        await _supabase.auth.signOut();

        if (!mounted) return;

        _mostrarMensagem(
          'Acesso negado: este usuário não está autorizado '
          'como administrador.',
          Colors.red,
        );

        return;
      }

      debugPrint('=================================================');
      debugPrint('[ADMIN LOGIN] ADMINISTRADOR AUTORIZADO');
      debugPrint(
        '[ADMIN LOGIN] ID admin tabela = ${adminEncontrado['id']}',
      );
      debugPrint(
        '[ADMIN LOGIN] E-mail admin tabela = ${adminEncontrado['email']}',
      );
      debugPrint(
        '[ADMIN LOGIN] auth.uid atual = '
        '${_supabase.auth.currentUser?.id}',
      );
      debugPrint(
        '[ADMIN LOGIN] sessão atual existe = '
        '${_supabase.auth.currentSession != null}',
      );
      debugPrint('=================================================');

      // ================================================================
      // 6. GARANTIA FINAL ANTES DE ABRIR O PAINEL
      // ================================================================
      if (_supabase.auth.currentUser == null ||
          _supabase.auth.currentSession == null) {
        throw Exception(
          'A sessão administrativa foi perdida antes de abrir o painel.',
        );
      }

      if (!mounted) return;

      // ================================================================
      // 7. ABRE O PAINEL SEM FAZER SIGNOUT
      //
      // IMPORTANTE:
      // A sessão autenticada permanece ativa.
      // Assim ConfiguracoesPage poderá acessar:
      //
      // Supabase.instance.client.auth.currentUser
      //
      // e o RLS reconhecerá o usuário como authenticated.
      // ================================================================
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ConfiguracoesPage(),
        ),
      );
    } on AuthException catch (e) {
      debugPrint(
        '[ADMIN LOGIN] AuthException: ${e.message}',
      );

      if (!mounted) return;

      String mensagem = 'Erro ao realizar login.';

      final textoErro = e.message.toLowerCase();

      if (textoErro.contains('invalid login credentials')) {
        mensagem = 'E-mail ou senha incorretos.';
      } else if (textoErro.contains('email not confirmed')) {
        mensagem = 'O e-mail ainda não foi confirmado no Supabase.';
      } else {
        mensagem = 'Erro no login: ${e.message}';
      }

      _mostrarMensagem(
        mensagem,
        Colors.red,
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[ADMIN LOGIN] Erro: $e',
      );

      debugPrint(
        '[ADMIN LOGIN] StackTrace: $stackTrace',
      );

      if (!mounted) return;

      _mostrarMensagem(
        'Erro no login: $e',
        Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  void _mostrarMensagem(
    String mensagem,
    Color cor,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF101B2B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: Color(0xFFFF8C00),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Painel Administrativo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ache Obra',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 25),

                  // ======================================================
                  // E-MAIL
                  // ======================================================
                  TextField(
                    controller: _emailController,
                    enabled: !_carregando,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'E-mail de Administrador',
                      labelStyle: TextStyle(
                        color: Colors.white54,
                      ),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: Color(0xFFFF8C00),
                      ),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.white12,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFFF8C00),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // ======================================================
                  // SENHA
                  // ======================================================
                  TextField(
                    controller: _senhaController,
                    enabled: !_carregando,
                    obscureText: _ocultarSenha,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_carregando) {
                        _fazerLoginAdmin();
                      }
                    },
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      labelStyle: const TextStyle(
                        color: Colors.white54,
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFFF8C00),
                      ),
                      suffixIcon: IconButton(
                        tooltip:
                            _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: _carregando
                            ? null
                            : () {
                                setState(() {
                                  _ocultarSenha = !_ocultarSenha;
                                });
                              },
                        icon: Icon(
                          _ocultarSenha
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.white54,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white12,
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.white12,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFFF8C00),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // ======================================================
                  // BOTÃO
                  // ======================================================
                  ElevatedButton(
                    onPressed: _carregando ? null : _fazerLoginAdmin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00),
                      disabledBackgroundColor:
                          const Color(0xFFFF8C00).withOpacity(0.45),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _carregando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'ENTRAR NO PAINEL',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
