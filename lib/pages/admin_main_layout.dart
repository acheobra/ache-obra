import 'package:flutter/material.dart';
import 'admin_planos_page.dart'; // Importa a tela de planos que criamos

class AdminMainLayout extends StatefulWidget {
  const AdminMainLayout({super.key});

  @override
  State<AdminMainLayout> createState() => _AdminMainLayoutState();
}

class _AdminMainLayoutState extends State<AdminMainLayout> {
  int _selectedIndex = 0;

  // Lista de telas/abas do seu painel administrativo
  // Conforme for criando novas telas de configuração, basta adicioná-las aqui!
  final List<Widget> _telas = [
    const AdminDashboardPage(), // Aba 0: Visão Geral / Dashboard
    const AdminPlanosPageContent(), // Aba 1: Gerenciamento de Planos
    const AdminConfiguracoesFuturasPage(), // Aba 2: Espaço para futuras configs
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a2c42),
      body: Row(
        children: [
          // Menu Lateral Fixo (Ideal para Web)
          Container(
            width: 260,
            color: const Color(0xFF253c59),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    "PAINEL ADMIN",
                    style: TextStyle(
                      color: Color(0xFFff9800),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    children: [
                      _buildMenuItem(0, Icons.dashboard_outlined, "Dashboard"),
                      _buildMenuItem(1, Icons.card_membership, "Planos"),
                      _buildMenuItem(2, Icons.settings_outlined, "Configurações"),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Ache Obra v1.0",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // Área de Conteúdo Principal (Muda conforme o menu clicado)
          Expanded(
            child: Container(
              color: const Color(0xFF1a2c42),
              child: _telas[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title) {
    final bool isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFFff9800) : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.white12,
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }
}

// ==========================================
// 1. TELA DE DASHBOARD (VISÃO GERAL)
// ==========================================
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Dashboard",
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildCardInfo("Usuários Ativos", "1,240", Icons.people),
              const SizedBox(width: 20),
              _buildCardInfo("Planos Vendidos", "312", Icons.shopping_cart),
              const SizedBox(width: 20),
              _buildCardInfo("Faturamento", "R$ 45.900", Icons.attach_money),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardInfo(String titulo, String valor, IconData icone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                Icon(icone, color: const Color(0xFFff9800)),
              ],
            ),
            const SizedBox(height: 10),
            Text(valor, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. CONTEÚDO DA TELA DE PLANOS (Ajustada para o Layout)
// ==========================================
class AdminPlanosPageContent extends StatefulWidget {
  const AdminPlanosPageContent({super.key});

  @override
  State<AdminPlanosPageContent> createState() => _AdminPlanosPageContentState();
}

class _AdminPlanosPageContentState extends State<AdminPlanosPageContent> {
  // Cole aqui todo o código da lógica de planos (formulário + listagem do Supabase) que passamos anteriormente.
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "Aqui entra o seu formulário e listagem de Planos integrado ao Supabase",
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}

// ==========================================
// 3. ABA DE CONFIGURAÇÕES FUTURAS (Exemplo)
// ==========================================
class AdminConfiguracoesFuturasPage extends StatelessWidget {
  const AdminConfiguracoesFuturasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32.0),
      child: Text(
        "Outras Configurações do Sistema (Em breve)",
        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}