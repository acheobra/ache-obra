import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class ListaConversasPage extends StatefulWidget {
  final Map<String, dynamic>? orcamentoParaEnviar;

  const ListaConversasPage({
    super.key,
    this.orcamentoParaEnviar,
  });

  @override
  State<ListaConversasPage> createState() => _ListaConversasPageState();
}

class _ListaConversasPageState extends State<ListaConversasPage> {
  String get meuId => Supabase.instance.client.auth.currentUser?.id ?? '';
  late Future<List<Map<String, dynamic>>> _futureConversas;

  @override
  void initState() {
    super.initState();
    _recarregarConversas();
  }

  void _recarregarConversas() {
    setState(() {
      _futureConversas = _buscarConversas();
    });
  }

  Future<List<Map<String, dynamic>>> _buscarConversas() async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('tab_conversas')
        .select('''
          id,
          created_at,
          demanda_id,
          cliente_id,
          outro_usuario_id
        ''')
        .or('cliente_id.eq.$meuId,outro_usuario_id.eq.$meuId')
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> conversas =
        List<Map<String, dynamic>>.from(response);

    for (var conversa in conversas) {
      final outroId = conversa['cliente_id'] == meuId
          ? conversa['outro_usuario_id']
          : conversa['cliente_id'];

      try {
        var usuarioData = await supabase
            .from('tab_usuarios')
            .select('usuario_nome, foto_url')
            .eq('id', outroId)
            .maybeSingle();

        if (usuarioData == null) {
          usuarioData = await supabase
              .from('tab_usuarios_profissionais')
              .select('usuario_nome, foto_url')
              .eq('id', outroId)
              .maybeSingle();
        }

        conversa['nome_outro'] = usuarioData?['usuario_nome'] ?? 'Usuário';
        conversa['foto_outro'] = usuarioData?['foto_url'];
      } catch (_) {
        conversa['nome_outro'] = 'Usuário';
        conversa['foto_outro'] = null;
      }

      try {
        final countRes = await supabase
            .from('tab_mensagens')
            .count(CountOption.exact)
            .eq('conversa_id', conversa['id'])
            .neq('remetente_id', meuId)
            .eq('lida', false);

        int qtd = countRes;
        conversa['qtd_nao_lidas'] = qtd;
        conversa['tem_nao_lida'] = qtd > 0;
      } catch (_) {
        conversa['qtd_nao_lidas'] = 0;
        conversa['tem_nao_lida'] = false;
      }
    }

    return conversas;
  }

  Future<void> _excluirConversa(int conversaId) async {
    try {
      await Supabase.instance.client
          .from('tab_mensagens')
          .delete()
          .eq('conversa_id', conversaId);

      await Supabase.instance.client
          .from('tab_conversas')
          .delete()
          .eq('id', conversaId);

      _recarregarConversas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Conversa excluída com sucesso.")),
        );
      }
    } catch (e) {
      debugPrint("Erro ao excluir conversa: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erro ao excluir conversa.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF253c59),
        title: Text(
          widget.orcamentoParaEnviar != null
              ? "Escolha a Conversa para Enviar"
              : "Minhas Conversas",
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureConversas,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text("Erro ao carregar conversas: ${snapshot.error}",
                  style: const TextStyle(color: Colors.redAccent)),
            );
          }

          final conversas = snapshot.data ?? [];
          if (conversas.isEmpty) {
            return const Center(
              child: Text(
                "Você ainda não possui nenhuma conversa.",
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            itemCount: conversas.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final conv = conversas[index];
              final nomeOutro = conv['nome_outro'] ?? 'Chat';
              final fotoUrl = conv['foto_outro'];
              final bool temNaoLida = conv['tem_nao_lida'] ?? false;
              final int qtdNaoLidas = conv['qtd_nao_lidas'] ?? 0;

              return GestureDetector(
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1A2C42),
                      title: const Text("Excluir Conversa",
                          style: TextStyle(color: Colors.white)),
                      content: const Text(
                          "Deseja realmente excluir esta conversa? Todas as mensagens serão apagadas.",
                          style: TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancelar",
                              style: TextStyle(color: Colors.white54)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent),
                          onPressed: () {
                            Navigator.pop(context);
                            _excluirConversa(conv['id']);
                          },
                          child: const Text("Excluir",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF253c59),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: temNaoLida
                          ? const Color(0xFFFF8C00)
                          : Colors.transparent,
                      width: temNaoLida ? 2.0 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white12,
                      backgroundImage: (fotoUrl != null &&
                              fotoUrl.toString().trim().isNotEmpty)
                          ? NetworkImage(fotoUrl)
                          : null,
                      child:
                          (fotoUrl == null || fotoUrl.toString().trim().isEmpty)
                              ? const Icon(Icons.person,
                                  color: Colors.white, size: 26)
                              : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            nomeOutro,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: temNaoLida
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (temNaoLida)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8C00),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$qtdNaoLidas',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios,
                        color: Colors.white54, size: 16),
                    onTap: () async {
                      await Supabase.instance.client
                          .from('tab_mensagens')
                          .update({'lida': true})
                          .eq('conversa_id', conv['id'])
                          .neq('remetente_id', meuId);

                      if (context.mounted) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              conversaId: conv['id'],
                              tituloOutroUsuario: nomeOutro,
                              orcamentoParaEnviar: widget.orcamentoParaEnviar,
                            ),
                          ),
                        );
                        _recarregarConversas();
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
