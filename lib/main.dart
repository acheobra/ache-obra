import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'cadastro_cliente_page.dart';
import 'cadastro_profissional_page.dart';
import 'cadastro_arquiteto_page.dart';
import 'cadastro_engenheiro_page.dart';
import 'pages/feed_page.dart';
import 'pages/cliente_home_page.dart';
import 'pages/planos_usuario_page.dart';
import 'pages/lista_conversas_page.dart';
import 'login_page.dart';
import 'pages/configuracoes_page.dart';
import 'pages/main_dashboard_page.dart';
import 'notification_service.dart';
import 'pages/ia_page.dart';
import 'pages/suporte_email_page.dart';
import 'pages/politica_privacidade_page.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    await Firebase.initializeApp();
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Chave global usada para abrir a tela escolhida no Admin ao tocar no push.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Guarda temporariamente um destino quando o push é tocado antes de a
/// navegação principal estar pronta (por exemplo, app totalmente fechado).
String? _destinoPushPendente;

/// FUNÇÃO PARA OBTER E SALVAR O TOKEN DO FCM NO SUPABASE
Future<void> salvarTokenFcmNoSupabase() async {
  if (kIsWeb) return; // FCM costuma ser focado em mobile (Android/iOS)
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Antes de registrar/atualizar o FCM, confirma que a conta está ativa.
    // É uma consulta pequena, executada somente nos momentos em que o token
    // seria salvo, e evita tratar conta bloqueada/inativa como sessão normal.
    try {
      final dadosUsuario = await Supabase.instance.client
          .from('tab_usuarios')
          .select('usuario_status')
          .eq('id', user.id)
          .maybeSingle();

      final status = (dadosUsuario?['usuario_status'] ?? 'ativo')
          .toString()
          .trim()
          .toLowerCase();

      if (status.isNotEmpty && status != 'ativo') {
        debugPrint(
          'FCM não atualizado: usuário com status "$status".',
        );
        return;
      }
    } catch (e) {
      // Falha de validação não deve travar a inicialização do aplicativo.
      // O UsuarioStatusGate continua responsável por bloquear o Feed.
      debugPrint('Não foi possível validar status antes do FCM: $e');
    }

    // Solicita permissão de notificações (essencial para iOS e Android 13+)
    NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        debugPrint('FCM Token obtido: $fcmToken');

        // Atualiza na tabela tab_usuarios do Supabase
        await Supabase.instance.client
            .from('tab_usuarios')
            .update({'fcm_token': fcmToken}).eq('id', user.id);

        debugPrint(
            'FCM Token salvo com sucesso no Supabase para o usuário: ${user.id}');
      }
    }
  } catch (e) {
    debugPrint('Erro ao salvar token FCM no Supabase: $e');
  }
}

Future<void>? _firebaseInitializationFuture;

/// Inicializa somente o que é indispensável antes do primeiro frame.
/// O Supabase precisa estar pronto antes do MaterialApp porque a
/// navegação inicial depende da sessão autenticada.
Future<void> asyncInitialization() async {
  await Supabase.initialize(
    url: 'https://ngmullubdvzzrueocxhd.supabase.co',
    publishableKey: 'sb_publishable_rUNfFcMVO6-oCWdv4DEgHw_bQT1sXU6',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );
}

/// Inicializa Firebase e notificações depois que a interface já começou
/// a ser montada, evitando segurar a abertura visual do aplicativo.
Future<void> _inicializarServicosEmSegundoPlano() async {
  if (kIsWeb) {
    return;
  }

  try {
    await Firebase.initializeApp();
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Erro ao inicializar Firebase/Notificações: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await asyncInitialization();

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );
  }

  runApp(const MyApp());

  if (!kIsWeb) {
    _firebaseInitializationFuture = _inicializarServicosEmSegundoPlano();
    unawaited(_firebaseInitializationFuture!);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _eLinkRecuperacao = false;
  StreamSubscription<RemoteMessage>? _pushOpenedSubscription;
  StreamSubscription<AuthState>? _authPushSubscription;
  bool _pushNavigationConfigured = false;

  @override
  void initState() {
    super.initState();
    _checarSeELinkRecuperacao();

    if (!kIsWeb) {
      unawaited(_configurarNavegacaoGlobalDePush());
    }

    // Tenta salvar o token caso o app abra já com usuário logado,
    // mas somente depois do primeiro frame e após o Firebase estar pronto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        unawaited(
          () async {
            try {
              final initFuture = _firebaseInitializationFuture;

              if (initFuture != null) {
                await initFuture;
              }

              await salvarTokenFcmNoSupabase();
            } catch (e) {
              debugPrint(
                'Erro ao atualizar token FCM após primeiro frame: $e',
              );
            }
          }(),
        );
      }
    });
  }

  Future<void> _configurarNavegacaoGlobalDePush() async {
    if (_pushNavigationConfigured) return;
    _pushNavigationConfigured = true;

    try {
      final initFuture = _firebaseInitializationFuture;
      if (initFuture != null) {
        await initFuture;
      } else {
        await Firebase.initializeApp();
      }

      _pushOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage message) {
          final destino = _extrairDestinoPush(message.data);
          if (destino != null) {
            _agendarNavegacaoPush(destino);
          }
        },
        onError: (Object erro) {
          debugPrint('Erro ao tratar abertura por push: $erro');
        },
      );

      final mensagemInicial =
          await FirebaseMessaging.instance.getInitialMessage();
      if (mensagemInicial != null) {
        final destino = _extrairDestinoPush(mensagemInicial.data);
        if (destino != null) {
          _agendarNavegacaoPush(destino);
        }
      }

      _authPushSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session != null && _destinoPushPendente != null) {
          final destino = _destinoPushPendente!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _abrirDestinoPush(destino);
          });
        }
      });
    } catch (e) {
      _pushNavigationConfigured = false;
      debugPrint('Erro ao configurar navegação global dos pushes: $e');
    }
  }

  String? _extrairDestinoPush(Map<String, dynamic> data) {
    final valor = data['deep_link'] ?? data['screen'];
    if (valor == null) return null;

    var destino = valor.toString().trim().toLowerCase();
    if (destino.isEmpty) return null;

    destino = destino
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');

    return destino;
  }

  void _agendarNavegacaoPush(String destino) {
    _destinoPushPendente = destino;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _abrirDestinoPush(destino);
    });
  }

  Future<String> _obterTipoUsuarioLogado() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'cliente';

    try {
      final dados = await Supabase.instance.client
          .from('tab_usuarios')
          .select('usuario_tipo')
          .eq('id', user.id)
          .maybeSingle();

      final tipo = (dados?['usuario_tipo'] ?? 'cliente').toString().trim();
      return tipo.isEmpty ? 'cliente' : tipo;
    } catch (e) {
      debugPrint('Erro ao obter tipo do usuário para abrir Planos: $e');
      return 'cliente';
    }
  }

  Future<void> _abrirDestinoPush(String destino) async {
    if (kIsWeb) return;

    // Não tenta abrir telas internas sem uma sessão autenticada.
    if (Supabase.instance.client.auth.currentSession == null) {
      _destinoPushPendente = destino;
      debugPrint(
        'Push aguardando login para abrir destino: $destino',
      );
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _destinoPushPendente = destino;
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (_destinoPushPendente == destino) {
          _abrirDestinoPush(destino);
        }
      });
      return;
    }

    try {
      Widget pagina;

      switch (destino) {
        case 'feed':
        case 'inicio':
        case 'home':
          pagina = const FeedPage();
          break;

        case 'meus_servicos':
        case 'meus_servicos_postagem':
        case 'postar_servico':
        case 'servicos':
          pagina = const ClienteHomePage(abaInicial: 1);
          break;

        case 'planos':
        case 'meus_planos':
        case 'assinatura':
          final tipoUsuario = await _obterTipoUsuarioLogado();
          pagina = PlanosUsuarioPage(tipoUsuarioLogado: tipoUsuario);
          break;

        case 'jisa':
        case 'jisa_ia':
          pagina = const IaPage();
          break;

        case 'chat':
        case 'mensagens':
        case 'minhas_mensagens':
        case 'conversas':
          pagina = const ListaConversasPage();
          break;

        case 'perfil':
        case 'editar_perfil':
        case 'meu_perfil':
          pagina = const ClienteHomePage(abaInicial: 0);
          break;

        default:
          debugPrint('Destino de push desconhecido: $destino');
          _destinoPushPendente = null;
          return;
      }

      _destinoPushPendente = null;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => pagina,
          settings: RouteSettings(name: '/push/$destino'),
        ),
      );

      debugPrint('Push abriu o destino: $destino');
    } catch (e, stackTrace) {
      _destinoPushPendente = destino;
      debugPrint('Erro ao abrir destino do push "$destino": $e');
      debugPrint('$stackTrace');
    }
  }

  void _checarSeELinkRecuperacao() {
    final urlAtual = Uri.base.toString();
    if (urlAtual.contains('type=recovery') ||
        urlAtual.contains('code=') ||
        urlAtual.contains('error_description') ||
        urlAtual.contains('#access_token=')) {
      setState(() {
        _eLinkRecuperacao = true;
      });
    }

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        setState(() {
          _eLinkRecuperacao = true;
        });
      }

      // SE O USUÁRIO ACABOU DE FAZER LOGIN, SALVA O TOKEN DO FCM AUTOMATICAMENTE
      // após o Firebase estar inicializado.
      if (data.event == AuthChangeEvent.signedIn && !kIsWeb) {
        unawaited(
          () async {
            try {
              final initFuture = _firebaseInitializationFuture;

              if (initFuture != null) {
                await initFuture;
              }

              await salvarTokenFcmNoSupabase();
            } catch (e) {
              debugPrint(
                'Erro ao salvar token FCM após login: $e',
              );
            }
          }(),
        );
      }
    });
  }

  @override
  void dispose() {
    _pushOpenedSubscription?.cancel();
    _authPushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Ache Obra',
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

          final urlAtual = Uri.base.toString();
          final hostAtual = Uri.base.host;

          // 1. Rota para Política de Privacidade
          if (urlAtual.contains('politica')) {
            return const PoliticaPrivacidadePage();
          }

          // 2. Rota explicita para Login Admin
          if (urlAtual.contains('admin_login')) {
            return const AdminLoginPage();
          }

          final authState = snapshot.data;
          final event = authState?.event;
          final session = authState?.session;

          // 3. Link de Recuperação de Senha
          if (_eLinkRecuperacao || event == AuthChangeEvent.passwordRecovery) {
            return RedefinirSenhaPage(
              onConcluido: () {
                setState(() {
                  _eLinkRecuperacao = false;
                });
              },
            );
          }

          // 4. Somente no domínio de PRODUÇÃO WEB (app.acheobra.com.br) abre a Admin
          final eDominioWebProducao =
              kIsWeb && hostAtual.contains('acheobra.com.br');

          if (eDominioWebProducao) {
            if (session != null) {
              return const ConfiguracoesPage();
            }
            return const AdminLoginPage();
          }

          // 5. TESTE LOCAL (localhost) ou APLICATIVO MOBILE:
          // Antes de abrir o Feed, valida em tempo real o status do usuário.
          // Essa verificação usa somente o registro do usuário logado e não
          // interfere no fluxo administrativo.
          if (session != null) {
            return UsuarioStatusGate(
              userId: session.user.id,
              child: const FeedPage(),
            );
          }

          return const AcheObraHome();
        },
      ),
      routes: {
        '/config': (context) => const ConfiguracoesPage(),
        '/dashboard': (context) => const MainDashboardPage(),
        '/admin_login': (context) => const AdminLoginPage(),
        '/suporte': (context) => const SuporteEmailPage(),
        '/politica': (context) => const PoliticaPrivacidadePage(),
      },
    );
  }
}

// =====================================================================
// CONTROLE CENTRAL DE ACESSO DO USUÁRIO
// =====================================================================
// Faz uma única leitura inicial do registro do usuário e mantém uma escuta
// filtrada apenas pelo ID dele. Assim, se o administrador alterar
// usuario_status para inativo, bloqueado ou excluido, o acesso ao Feed é
// interrompido sem polling e sem consultas repetitivas.
//
// IMPORTANTE:
// - Não altera o fluxo do painel administrativo.
// - Não fica consultando o banco em loop.
// - Quando o usuário volta para "ativo", o acesso é liberado automaticamente.
// =====================================================================
class UsuarioStatusGate extends StatefulWidget {
  final String userId;
  final Widget child;

  const UsuarioStatusGate({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<UsuarioStatusGate> createState() => _UsuarioStatusGateState();
}

class _UsuarioStatusGateState extends State<UsuarioStatusGate> {
  StreamSubscription<List<Map<String, dynamic>>>? _statusSubscription;

  String _statusAtual = 'ativo';
  bool _carregandoStatusInicial = true;
  bool _consultaInicialConcluida = false;

  @override
  void initState() {
    super.initState();
    _inicializarControleDeStatus();
  }

  String _normalizarStatus(dynamic valor) {
    final status = (valor ?? 'ativo').toString().trim().toLowerCase();

    if (status == 'excluído') return 'excluido';
    return status;
  }

  Future<void> _inicializarControleDeStatus() async {
    await _consultarStatusInicial();
    _iniciarEscutaDeStatus();
  }

  Future<void> _consultarStatusInicial() async {
    String? statusEncontrado;

    // Faz poucas tentativas curtas somente na abertura. Uma falha temporária
    // de internet/Supabase não deve colocar um usuário válido numa tela de erro.
    for (int tentativa = 1; tentativa <= 2; tentativa++) {
      try {
        final dadosUsuario = await Supabase.instance.client
            .from('tab_usuarios')
            .select('usuario_status')
            .eq('id', widget.userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));

        if (dadosUsuario != null) {
          statusEncontrado = _normalizarStatus(dadosUsuario['usuario_status']);
        } else {
          // Mantém compatibilidade e evita bloquear o aplicativo por uma
          // resposta vazia momentânea.
          statusEncontrado = 'ativo';
        }

        break;
      } catch (e) {
        debugPrint(
          'Tentativa $tentativa ao consultar usuario_status falhou: $e',
        );

        if (tentativa < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
      }
    }

    if (!mounted) return;

    setState(() {
      // Se as duas tentativas falharem, não exibimos tela de erro e não
      // estragamos a entrada do usuário. O app entra normalmente e a escuta
      // em tempo real continua tentando receber o status posteriormente.
      if (statusEncontrado != null) {
        _statusAtual = statusEncontrado;
      }

      _carregandoStatusInicial = false;
      _consultaInicialConcluida = true;
    });
  }

  void _iniciarEscutaDeStatus() {
    _statusSubscription?.cancel();

    try {
      _statusSubscription = Supabase.instance.client
          .from('tab_usuarios')
          .stream(primaryKey: ['id'])
          .eq('id', widget.userId)
          .listen(
            (registros) {
              if (!mounted || registros.isEmpty) return;

              final novoStatus =
                  _normalizarStatus(registros.first['usuario_status']);

              if (novoStatus == _statusAtual) return;

              setState(() {
                _statusAtual = novoStatus;
              });

              debugPrint(
                'Status do usuário atualizado em tempo real: $_statusAtual',
              );
            },
            onError: (Object erro, StackTrace stackTrace) {
              // Uma queda do Realtime NÃO substitui o último status válido e
              // NÃO mostra tela de erro ao usuário.
              debugPrint(
                'Escuta de usuario_status temporariamente indisponível: $erro',
              );
            },
          );
    } catch (e) {
      // A consulta inicial já protege a entrada. Se o Realtime estiver
      // indisponível, o usuário não verá uma tela de erro por causa disso.
      debugPrint('Não foi possível iniciar escuta de usuario_status: $e');
    }
  }

  @override
  void didUpdateWidget(covariant UsuarioStatusGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userId != widget.userId) {
      _statusSubscription?.cancel();

      _statusAtual = 'ativo';
      _carregandoStatusInicial = true;
      _consultaInicialConcluida = false;

      _inicializarControleDeStatus();
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mostra apenas um carregamento discreto enquanto fazemos a primeira
    // validação. Não existe mais tela "Não foi possível validar sua conta".
    if (_carregandoStatusInicial && !_consultaInicialConcluida) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A2C42),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF8C00),
          ),
        ),
      );
    }

    final status = _normalizarStatus(_statusAtual);

    if (status == 'bloqueado') {
      return const _TelaStatusUsuario(
        titulo: 'CONTA BLOQUEADA',
        mensagem:
            'Sua conta foi bloqueada por descumprir as políticas da plataforma Ache Obra.\n\n'
            'Para mais informações ou esclarecimentos, entre em contato pelo e-mail:\n'
            'suporte@acheobra.com.br',
        icone: Icons.block_rounded,
        corDestaque: Colors.redAccent,
      );
    }

    if (status == 'inativo') {
      return const _TelaStatusUsuario(
        titulo: 'CONTA INATIVA',
        mensagem: 'Sua conta está temporariamente inativa.\n\n'
            'Para mais informações ou esclarecimentos, entre em contato pelo e-mail:\n'
            'suporte@acheobra.com.br',
        icone: Icons.pause_circle_outline_rounded,
        corDestaque: Colors.orange,
      );
    }

    if (status == 'excluido') {
      return const _TelaStatusUsuario(
        titulo: 'CONTA INDISPONÍVEL',
        mensagem:
            'Este cadastro está marcado como excluído e não possui acesso ao aplicativo.\n\n'
            'Para mais informações, entre em contato pelo e-mail:\n'
            'suporte@acheobra.com.br',
        icone: Icons.delete_forever_outlined,
        corDestaque: Colors.redAccent,
      );
    }

    // Status ativo, vazio, desconhecido ou falha temporária de comunicação:
    // não exibe tela de erro. O aplicativo continua funcionando normalmente.
    //
    // Os estados administrativos que realmente restringem o acesso são
    // tratados explicitamente acima.
    return widget.child;
  }
}

class _TelaStatusUsuario extends StatelessWidget {
  final String titulo;
  final String mensagem;
  final IconData icone;
  final Color corDestaque;

  const _TelaStatusUsuario({
    required this.titulo,
    required this.mensagem,
    required this.icone,
    required this.corDestaque,
  });

  Future<void> _sair() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Erro ao encerrar sessão de usuário restrito: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF101B2B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: corDestaque.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icone,
                    color: corDestaque,
                    size: 72,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: corDestaque,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sair,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'SAIR',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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

// =====================================================================
// FUNÇÃO UNIVERSAL DE SOLICITAÇÃO DE RECUPERAÇÃO DE SENHA (COM StatefulBuilder)
// =====================================================================
void mostrarDialogoEsqueciSenhaGlobal(BuildContext context,
    [String? emailInicial]) {
  final emailController = TextEditingController(
    text:
        emailInicial ?? Supabase.instance.client.auth.currentUser?.email ?? '',
  );

  bool emailEnviado = false;
  bool carregando = false;
  bool emailNaoCadastrado = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
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
                  icon: const Icon(Icons.close, color: Colors.white70),
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
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            enabled: !carregando,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [],
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              labelText: 'E-MAIL',
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.email_outlined,
                                  color: Color(0xFFFF8C00)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
            actions: [
              if (!emailEnviado && !emailNaoCadastrado) ...[
                TextButton(
                  onPressed:
                      carregando ? null : () => Navigator.pop(dialogContext),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Informe o e-mail!'),
                                  backgroundColor: Colors.orange),
                            );
                            return;
                          }

                          setStateDialog(() {
                            carregando = true;
                          });

                          try {
                            await Supabase.instance.client.auth
                                .resetPasswordForEmail(email);

                            if (dialogContext.mounted) {
                              setStateDialog(() {
                                carregando = false;
                                emailEnviado = true;
                              });
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setStateDialog(() {
                                carregando = false;
                              });
                            }

                            if (context.mounted) {
                              String mensagemErro = 'Erro ao enviar e-mail.';

                              if (error
                                  .toString()
                                  .contains('over_email_send_rate_limit')) {
                                mensagemErro =
                                    'Muitas tentativas recentes. Verifique seu e-mail (ou SPAM) ou aguarde alguns instantes.';
                              } else {
                                mensagemErro = 'Erro: $error';
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
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
}

// =====================================================================
// TELA DE REDEFINIÇÃO DE SENHA
// =====================================================================
class RedefinirSenhaPage extends StatefulWidget {
  final VoidCallback onConcluido;
  const RedefinirSenhaPage({super.key, required this.onConcluido});

  @override
  State<RedefinirSenhaPage> createState() => _RedefinirSenhaPageState();
}

class _RedefinirSenhaPageState extends State<RedefinirSenhaPage> {
  final _novaSenhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  bool _ocultarSenha1 = true;
  bool _ocultarSenha2 = true;
  bool _carregando = false;
  bool _sucesso = false;

  Future<void> _salvarNovaSenha() async {
    final senha = _novaSenhaController.text.trim();
    final confirmar = _confirmarSenhaController.text.trim();

    if (senha.isEmpty || confirmar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha os dois campos de senha!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (senha.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha deve ter pelo menos 6 caracteres.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (senha != confirmar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não coincidem! Digite novamente.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _carregando = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: senha),
      );

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;
      setState(() {
        _sucesso = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao redefinir senha: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF101B2B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: _sucesso
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 70,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Senha Alterada com Sucesso!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "Sua nova senha foi cadastrada com sucesso. Você já pode fechar esta página e fazer login pelo aplicativo Ache Obra no seu celular.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C00),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            widget.onConcluido();
                          },
                          child: const Text(
                            "IR PARA O LOGIN ADMIN",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Redefinir Senha",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "Digite e confirme sua nova senha abaixo:",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _novaSenhaController,
                        obscureText: _ocultarSenha1,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Nova Senha",
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white12,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _ocultarSenha1
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              setState(() {
                                _ocultarSenha1 = !_ocultarSenha1;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _confirmarSenhaController,
                        obscureText: _ocultarSenha2,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Confirmar Nova Senha",
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white12,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _ocultarSenha2
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              setState(() {
                                _ocultarSenha2 = !_ocultarSenha2;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      ElevatedButton(
                        onPressed: _carregando ? null : _salvarNovaSenha,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _carregando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "SALVAR NOVA SENHA",
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
    );
  }
}

// =====================================================================
// TELA DE LOGIN EXCLUSIVA PARA ADMINISTRAÇÃO VIA WEB (COM RPC)
// =====================================================================
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _carregando = false;
  bool _ocultarSenha = true;
  final _supabase = Supabase.instance.client;

  Future<void> _fazerLoginAdmin() async {
    if (_carregando) return;

    final email = _emailController.text.trim().toLowerCase();
    final senha = _senhaController.text;

    if (email.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha o e-mail e a senha!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _carregando = true);

    try {
      final AuthResponse authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: senha,
      );

      final User? user = authResponse.user;
      final Session? session = authResponse.session;

      if (user == null || session == null) {
        throw Exception(
          'Não foi possível criar uma sessão autenticada no Supabase.',
        );
      }

      debugPrint(
          '============================================================');
      debugPrint('[ADMIN LOGIN] LOGIN NO SUPABASE AUTH REALIZADO');
      debugPrint('[ADMIN LOGIN] auth.uid=${user.id}');
      debugPrint('[ADMIN LOGIN] email=${user.email}');
      debugPrint('[ADMIN LOGIN] session=true');
      debugPrint(
          '============================================================');

      Map<String, dynamic>? adminEncontrado;

      final dynamic adminPorEmail = await _supabase
          .from('tab_admin_users')
          .select('*')
          .ilike('email', email)
          .maybeSingle();

      if (adminPorEmail != null) {
        adminEncontrado = Map<String, dynamic>.from(adminPorEmail);
      }

      if (adminEncontrado == null) {
        final dynamic adminPorId = await _supabase
            .from('tab_admin_users')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        if (adminPorId != null) {
          adminEncontrado = Map<String, dynamic>.from(adminPorId);
        }
      }

      if (adminEncontrado == null) {
        await _supabase.auth.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Acesso negado: este usuário não é um administrador autorizado.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      debugPrint(
        '[ADMIN LOGIN] Administrador autorizado: '
        '${adminEncontrado['nome'] ?? adminEncontrado['email'] ?? user.email}',
      );
      debugPrint(
        '[ADMIN LOGIN] Sessão antes de abrir painel: '
        '${_supabase.auth.currentSession != null}',
      );
      debugPrint(
        '[ADMIN LOGIN] currentUser antes de abrir painel: '
        '${_supabase.auth.currentUser?.id}',
      );

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/dashboard');
    } on AuthException catch (e) {
      debugPrint('[ADMIN LOGIN] AuthException: ${e.message}');

      if (!mounted) return;

      String mensagem = 'Erro no login: ${e.message}';
      final erro = e.message.toLowerCase();

      if (erro.contains('invalid login credentials')) {
        mensagem = 'E-mail ou senha incorretos!';
      } else if (erro.contains('email not confirmed')) {
        mensagem = 'O e-mail do administrador ainda não foi confirmado.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[ADMIN LOGIN] Erro ao fazer login: $e');
      debugPrint('[ADMIN LOGIN] StackTrace: $stackTrace');

      try {
        if (_supabase.auth.currentUser != null) {
          await _supabase.auth.signOut();
        }
      } catch (_) {}

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao conectar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF101B2B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Painel Administrativo",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  enabled: !_carregando,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "E-mail de Administrador",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Senha",
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white12,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
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
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: _carregando ? null : _fazerLoginAdmin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _carregando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "ENTRAR NO PAINEL",
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
    );
  }
}

// =====================================================================
// TELA INICIAL DO APP (MOBILE / LOCALHOST)
// =====================================================================
class AcheObraHome extends StatelessWidget {
  const AcheObraHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("🇧🇷", style: TextStyle(fontSize: 30)),
                ],
              ),
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
                onPressed: () => mostrarDialogoEsqueciSenhaGlobal(context),
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
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
