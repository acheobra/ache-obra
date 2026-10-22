import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'configuracoes_page.dart'; // Importa a tela de configurações na mesma pasta

class MainDashboardPage extends StatefulWidget {
  const MainDashboardPage({super.key});

  @override
  State<MainDashboardPage> createState() => _MainDashboardPageState();
}

class _MainDashboardPageState extends State<MainDashboardPage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      salvarTokenFCM();
    });
  }

  Future<void> salvarTokenFCM() async {
    print("--- DEBUG FCM: Iniciando rotina de salvamento ---");
    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Pede permissão
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print(
          "--- DEBUG FCM: Status da permissão: ${settings.authorizationStatus} ---");

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // 2. Coleta o Token do dispositivo
        String? token = await messaging.getToken();
        print("--- DEBUG FCM: Token gerado: $token ---");

        final user = Supabase.instance.client.auth.currentUser;
        print("--- DEBUG FCM: Auth User ID atual: ${user?.id} ---");

        if (token != null && user != null) {
          // 3. Executa o Update e verifica se afetou alguma linha
          final response = await Supabase.instance.client
              .from('tab_usuarios')
              .update({'fcm_token': token})
              .eq('id', user.id)
              .select(); // O .select() retorna os dados atualizados para validação

          print("--- DEBUG FCM: Resposta do Supabase: $response ---");

          if (response == null || (response as List).isEmpty) {
            print(
                "--- ATENÇÃO: O Update rodou, mas NENHUMA linha foi alterada! Verifique se o ID do auth.users bate com o ID da tab_usuarios. ---");
          } else {
            print("--- SUCESSO: Token salvo com sucesso na tab_usuarios! ---");
          }
        } else {
          print("--- DEBUG FCM: Token ou usuário estão nulos. ---");
        }
      } else {
        print(
            "--- DEBUG FCM: Permissão de notificação negada pelo usuário. ---");
      }
    } catch (e) {
      print("--- ERRO CRÍTICO NO FCM: $e ---");
    }
  }

  // Lista de telas do painel web
  final List<Widget> _telas = [
    const InicioDashboardTab(),
    const ConfiguracoesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Menu Lateral Estilo Painel Web
          NavigationRail(
            backgroundColor: const Color(0xFF101B2B),
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            selectedIconTheme: const IconThemeData(color: Color(0xFFFF8C00)),
            unselectedIconTheme: const IconThemeData(color: Colors.white54),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFFFF8C00),
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Início'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Configurações'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white12),

          // Conteúdo Principal que muda conforme a aba selecionada
          Expanded(
            child: _telas[_currentIndex],
          ),
        ],
      ),
    );
  }
}

// Exemplo da Tela de Início / Dashboard do Ache Obra
class InicioDashboardTab extends StatelessWidget {
  const InicioDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A2C42),
      padding: const EdgeInsets.all(30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Bem-vindo ao Ache Obra",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Gerencie suas obras, clientes e profissionais por aqui.",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 30),
          // Cards de Resumo / Dashboard
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              children: [
                _buildCardResumo(
                    "Obras Ativas", "12", Icons.home_repair_service),
                _buildCardResumo("Profissionais", "48", Icons.people),
                _buildCardResumo(
                    "Solicitações", "5", Icons.notifications_active),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardResumo(String titulo, String valor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101B2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, color: const Color(0xFFFF8C00), size: 40),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
