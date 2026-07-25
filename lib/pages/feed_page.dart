import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cliente_home_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  String _filtroSelecionado = 'Todos';
  String? _servicoSelecionado;

  final List<String> _filtros = [
    'Todos',
    'Profissionais',
    'Arquitetos',
    'Engenheiros',
    'Serviços'
  ];

  final List<String> _listaServicosDisponiveis = [
    'Faz Tudo',
    'Impermeabilizador',
    'Encanador (Hidráulico)',
    'Eletricista',
    'Pintor Industrial',
    'Telhadista',
    'Carpinteiro',
    'Jardineiro',
    'Vidraceiro',
    'Serralheiro',
    'Azulejista',
    'Instalador de Ar Condicionado',
    'Gesseiro',
    'Pedreiro',
    'Pintor',
    'Mestre de Obras'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2C42),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text("Ache Obra",
            style: TextStyle(
                color: Color(0xFFFF8C00), fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filtroSelecionado,
                icon: const Icon(Icons.filter_list, color: Colors.white),
                dropdownColor: const Color(0xFF253c59),
                style: const TextStyle(color: Colors.white),
                items: _filtros.map((String value) {
                  return DropdownMenuItem<String>(
                      value: value, child: Text(value));
                }).toList(),
                onChanged: (val) {
                  if (val == 'Serviços') {
                    setState(() {
                      _filtroSelecionado = val!;
                    });
                    _mostrarModalSelecaoServico();
                  } else {
                    setState(() {
                      _filtroSelecionado = val!;
                      _servicoSelecionado = null;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A2C42),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF253c59)),
              child: Text('Menu do Cliente',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.white70),
              title: const Text("Editar Perfil",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ClienteHomePage()));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.handyman_outlined, color: Colors.white70),
              title: const Text("Contratar um Profissional",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white24),
          ],
        ),
      ),
      body: ListView(
        children: [
          if (_filtroSelecionado == 'Serviços' && _servicoSelecionado != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF253c59),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Filtrando por: $_servicoSelecionado",
                      style: const TextStyle(
                          color: Color(0xFFFF8C00),
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filtroSelecionado = 'Todos';
                        _servicoSelecionado = null;
                      });
                    },
                    child: const Text("Limpar",
                        style: TextStyle(color: Colors.white70)),
                  )
                ],
              ),
            ),
          SizedBox(
            height: 140,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _buscarDemandas(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    itemBuilder: (context, index) =>
                        _buildDestaqueCardPlaceholder("Exemplo ${index + 1}"),
                  );
                }

                final listaDestaques = snapshot.data!;

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount:
                      listaDestaques.length > 5 ? 5 : listaDestaques.length,
                  itemBuilder: (context, index) {
                    final demanda = listaDestaques[index];
                    return _buildDestaqueCardReal(context, demanda);
                  },
                );
              },
            ),
          ),
          const Divider(color: Colors.white24),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _buscarDemandas(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      "Erro ao carregar o feed: ${snapshot.error}",
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final demandas = snapshot.data ?? [];

              if (demandas.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                    child: Text(
                      "Nenhuma demanda encontrada.",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: demandas.length,
                itemBuilder: (context, index) {
                  final demanda = demandas[index];
                  return _buildServicoCard(context, demanda);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _mostrarModalSelecaoServico() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Selecione 1 Serviço",
                style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _listaServicosDisponiveis.length,
                  itemBuilder: (context, index) {
                    final servico = _listaServicosDisponiveis[index];
                    return ListTile(
                      title: Text(servico,
                          style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          color: Colors.white54, size: 16),
                      onTap: () {
                        setState(() {
                          _servicoSelecionado = servico;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _buscarDemandas() async {
    final supabase = Supabase.instance.client;

    var query = supabase
        .from('tab_demandas_clientes')
        .select('*, tab_usuarios(usuario_nome, whatsapp, foto_url)');

    if (_filtroSelecionado == 'Profissionais') {
      query = query.eq('tipo_profissional', 'Profissional');
    } else if (_filtroSelecionado == 'Arquitetos') {
      query = query.eq('tipo_profissional', 'Arquiteto');
    } else if (_filtroSelecionado == 'Engenheiros') {
      query = query.eq('tipo_profissional', 'Engenheiro');
    } else if (_filtroSelecionado == 'Serviços' &&
        _servicoSelecionado != null) {
      query = query.contains('servicos_desejados', [_servicoSelecionado]);
    }

    final response = await query.order('id', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Widget _buildDestaqueCardPlaceholder(String texto) {
    return Container(
      width: 110,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF253c59),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF8C00).withOpacity(0.5)),
      ),
      child: Center(
        child: Text(texto,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ),
    );
  }

  Widget _buildDestaqueCardReal(
      BuildContext context, Map<String, dynamic> demanda) {
    final dadosUsuario = demanda['tab_usuarios'] as Map<String, dynamic>?;
    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Destaque';
    final fotoUrl = dadosUsuario?['foto_url'];
    final tipo = demanda['tipo_profissional'] ?? 'Serviço';

    return GestureDetector(
      onTap: () {
        _abrirDetalhesDemanda(context, demanda, dadosUsuario);
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF8C00), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white12,
                  backgroundImage:
                      (fotoUrl != null && fotoUrl.toString().trim().isNotEmpty)
                          ? NetworkImage(fotoUrl)
                          : null,
                  child: (fotoUrl == null || fotoUrl.toString().trim().isEmpty)
                      ? const Icon(Icons.person,
                          color: Colors.white54, size: 28)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF8C00),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.star, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              nomeCliente,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              tipo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFF8C00), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicoCard(BuildContext context, Map<String, dynamic> demanda) {
    final tipo = demanda['tipo_profissional'] ?? '';
    final descricao = demanda['descricao_detalhada'] ?? 'Sem descrição';
    final cidade = demanda['cidade'] ?? '';
    final estado = demanda['estado'] ?? '';
    final bairro = demanda['bairro'] ?? '';

    final dadosUsuario = demanda['tab_usuarios'] as Map<String, dynamic>?;
    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Cliente';
    final fotoUrl = dadosUsuario?['foto_url'];

    List<dynamic> servicos = [];
    if (demanda['servicos_desejados'] != null) {
      servicos = demanda['servicos_desejados'] as List<dynamic>;
    }

    String localizacao = [bairro, cidade, estado]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' - ');

    return GestureDetector(
      onTap: () {
        _abrirDetalhesDemanda(context, demanda, dadosUsuario);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF253c59),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        fotoUrl != null && fotoUrl.toString().trim().isNotEmpty
                            ? Image.network(
                                fotoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person,
                                        color: Colors.white54, size: 30),
                              )
                            : const Icon(Icons.person,
                                color: Colors.white54, size: 30),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFF8C00)),
                        ),
                        child: Text(
                          tipo.toString().toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFFF8C00),
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "CLIENTE - Procurando Profissional",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nomeCliente,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (servicos.isNotEmpty) ...[
              Text(
                "Serviços: ${servicos.join(', ')}",
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              descricao,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (localizacao.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      color: Color(0xFFFF8C00), size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      localizacao,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                "Clique no Anúncio e Saiba Mais",
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDetalhesDemanda(BuildContext context, Map<String, dynamic> demanda,
      Map<String, dynamic>? dadosUsuario) {
    final tipo = demanda['tipo_profissional'] ?? '';
    final descricao = demanda['descricao_detalhada'] ?? 'Sem descrição';
    final cidade = demanda['cidade'] ?? '';
    final estado = demanda['estado'] ?? '';
    final bairro = demanda['bairro'] ?? '';
    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Cliente';
    final fotoUrl = dadosUsuario?['foto_url'];
    final whatsapp = dadosUsuario?['whatsapp'] ?? 'Não informado';

    List<dynamic> servicos = [];
    if (demanda['servicos_desejados'] != null) {
      servicos = demanda['servicos_desejados'] as List<dynamic>;
    }

    String localizacao = [bairro, cidade, estado]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' - ');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: fotoUrl != null &&
                              fotoUrl.toString().trim().isNotEmpty
                          ? Image.network(
                              fotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.person,
                                      color: Colors.white54, size: 35),
                            )
                          : const Icon(Icons.person,
                              color: Colors.white54, size: 35),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFF8C00)),
                          ),
                          child: Text(
                            tipo.toString().toUpperCase(),
                            style: const TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "CLIENTE - Procurando Profissional",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nomeCliente,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 10),
              if (servicos.isNotEmpty) ...[
                const Text(
                  "Serviços Desejados:",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  servicos.join(', '),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                "Descrição Detalhada:",
                style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                descricao,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (localizacao.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  "Localização:",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFFFF8C00), size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        localizacao,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                "Telefone / WhatsApp:",
                style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    whatsapp.toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _abrirWhatsApp(whatsapp.toString());
                  },
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: const Text(
                    "Entrar em Contato via WhatsApp",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _abrirWhatsApp(String numero) async {
    if (numero.isEmpty || numero == 'Não informado') {
      debugPrint("Número de WhatsApp não cadastrado.");
      return;
    }

    final numeroLimpo = numero.replaceAll(RegExp(r'\D'), '');
    const mensagem = "Tenho esse serviço para fazer, você está interessado?";

    final uri = Uri.parse(
        "https://api.whatsapp.com/send?phone=55$numeroLimpo&text=${Uri.encodeComponent(mensagem)}");

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final uriWeb = Uri.parse(
            "https://wa.me/55$numeroLimpo?text=${Uri.encodeComponent(mensagem)}");
        await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Erro ao abrir o WhatsApp: $e");
    }
  }
}
