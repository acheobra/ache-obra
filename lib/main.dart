import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cadastro_cliente_page.dart';
import 'cadastro_profissional_page.dart';
import 'cadastro_arquiteto_page.dart';
import 'cadastro_engenheiro_page.dart';
import 'pages/feed_page.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ngmullubdvzzrueocxhd.supabase.co',
    publishableKey: 'sb_publishable_rUNfFcMVO6-oCWdv4DEgHw_bQT1sXU6',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthState>(
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          Supabase.instance.client.auth.currentSession,
        ),
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF1A2C42),
              body: Center(
                  child: CircularProgressIndicator(color: Colors.orange)),
            );
          }
          final session = snapshot.data?.session;
          return session != null ? const FeedPage() : const AcheObraHome();
        },
      ),
    );
  }
}

class AcheObraHome extends StatelessWidget {
  const AcheObraHome({super.key});

  void _mostrarDialogoEsqueciSenha(BuildContext context) {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final ValueNotifier<bool> emailEnviadoNotifier =
            ValueNotifier<bool>(false);
        final ValueNotifier<bool> carregandoNotifier =
            ValueNotifier<bool>(false);
        final ValueNotifier<bool> emailNaoCadastradoNotifier =
            ValueNotifier<bool>(false);

        return ValueListenableBuilder<bool>(
          valueListenable: emailEnviadoNotifier,
          builder: (context, emailEnviado, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: carregandoNotifier,
              builder: (context, carregando, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: emailNaoCadastradoNotifier,
                  builder: (context, emailNaoCadastrado, _) {
                    String tituloDialogo = 'RECUPERAR SENHA';
                    if (emailEnviado) {
                      tituloDialogo = 'E-MAIL ENVIADO!';
                    } else if (emailNaoCadastrado) {
                      tituloDialogo = 'E-MAIL NÃO ENCONTRADO';
                    }

                    return AlertDialog(
                      backgroundColor: const Color(0xFF1A2C42),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tituloDialogo,
                            style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(dialogContext),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      content: emailEnviado
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mark_email_read,
                                    color: Colors.orange, size: 60),
                                SizedBox(height: 15),
                                Text(
                                  'E-mail enviado. Não deixe de olhar sua caixa de SPAM também!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : emailNaoCadastrado
                              ? const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.error_outline,
                                        color: Colors.redAccent, size: 60),
                                    SizedBox(height: 15),
                                    Text(
                                      'E-mail NÃO cadastrado, entre com o e-mail correto ou crie uma conta!',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Digite seu e-mail cadastrado para receber o link de redefinição:',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 14),
                                    ),
                                    const SizedBox(height: 15),
                                    TextField(
                                      controller: emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      enabled: !carregando,
                                      style:
                                          const TextStyle(color: Colors.black),
                                      decoration: InputDecoration(
                                        labelText: 'E-MAIL',
                                        filled: true,
                                        fillColor: Colors.white,
                                        prefixIcon: const Icon(
                                            Icons.email_outlined,
                                            color: Color(0xFFFF8C00)),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                ),
                      actions: [
                        if (!emailEnviado && !emailNaoCadastrado) ...[
                          TextButton(
                            onPressed: carregando
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: const Text('Cancelar',
                                style: TextStyle(color: Colors.white70)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF8C00)),
                            onPressed: carregando
                                ? null
                                : () async {
                                    final email = emailController.text.trim();
                                    if (email.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('Informe o e-mail!'),
                                            backgroundColor: Colors.orange),
                                      );
                                      return;
                                    }

                                    carregandoNotifier.value = true;

                                    try {
                                      final respostaBanco = await Supabase
                                          .instance.client
                                          .from('tab_usuarios')
                                          .select('email')
                                          .eq('email', email)
                                          .maybeSingle();

                                      if (respostaBanco == null) {
                                        if (dialogContext.mounted) {
                                          carregandoNotifier.value = false;
                                          emailNaoCadastradoNotifier.value =
                                              true;
                                        }
                                        return;
                                      }

                                      await Supabase.instance.client.auth
                                          .resetPasswordForEmail(email);

                                      if (dialogContext.mounted) {
                                        carregandoNotifier.value = false;
                                        emailEnviadoNotifier.value = true;
                                      }
                                    } catch (error) {
                                      if (dialogContext.mounted) {
                                        carregandoNotifier.value = false;
                                      }

                                      if (context.mounted) {
                                        String mensagemErro =
                                            'Erro ao enviar e-mail.';

                                        if (error.toString().contains(
                                            'over_email_send_rate_limit')) {
                                          mensagemErro =
                                              'Muitas tentativas recentes. Verifique seu e-mail (ou SPAM) ou aguarde alguns instantes.';
                                        } else {
                                          mensagemErro = 'Erro: $error';
                                        }

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(mensagemErro),
                                              backgroundColor: Colors.red),
                                        );
                                      }
                                    }
                                  },
                            child: carregando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('ENVIAR',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Align(
                  alignment: Alignment.topRight,
                  child: Text("🇧🇷", style: TextStyle(fontSize: 30))),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Image.asset('assets/Logo_ache_obra.png',
                    width: 150, height: 150, fit: BoxFit.contain),
              ),
              const Text("QUERO ME CADASTRAR",
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildButton(context, "SOU CLIENTE",
                  "Precisa de um serviço? Encontre profissionais."),
              _buildButton(context, "SOU PROFISSIONAL",
                  "É pedreiro, pintor, eletricista ou outros?"),
              _buildButton(
                  context, "SOU ARQUITETO(a)", "Planeje sonhos com segurança."),
              _buildButton(context, "SOU ENGENHEIRO(a) CIVIL",
                  "Projetos e execuções de obras."),
              const Divider(color: Colors.white24, height: 40),
              const Text("JÁ SOU CADASTRADO",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginPage())),
                  child: const Text("FAZER LOGIN",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _mostrarDialogoEsqueciSenha(context),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, String title, String desc) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF8C00),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10)),
        onPressed: () {
          if (title == "SOU CLIENTE") {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CadastroClientePage()),
            );
          } else if (title == "SOU PROFISSIONAL") {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CadastroProfissionalPage()),
            );
          } else if (title == "SOU ARQUITETO(a)") {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CadastroArquitetoPage()),
            );
          } else if (title == "SOU ENGENHEIRO(a) CIVIL") {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CadastroEngenheiroPage()),
            );
          }
        },
        child: Column(
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.black)),
            const SizedBox(height: 4),
            Text(desc,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
