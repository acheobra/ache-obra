import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvaliacaoModal extends StatefulWidget {
  final String prestadorId;

  const AvaliacaoModal({super.key, required this.prestadorId});

  @override
  State<AvaliacaoModal> createState() => _AvaliacaoModalState();
}

class _AvaliacaoModalState extends State<AvaliacaoModal> {
  int _notaSelecionada = 5;
  final TextEditingController _comentarioController = TextEditingController();
  bool _enviando = false;
  bool _carregandoDados = true;
  bool _jaTemAvaliacao = false;

  @override
  void initState() {
    super.initState();
    _carregarAvaliacaoExistente();
  }

  Future<void> _carregarAvaliacaoExistente() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Busca se o usuário já avaliou este profissional
      final response = await Supabase.instance.client
          .from('tab_avaliacoes')
          .select('nota, comentario')
          .eq('prestador_id', widget.prestadorId)
          .eq('cliente_id', user.id)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _notaSelecionada = (response['nota'] ?? 5) as int;
          _comentarioController.text = response['comentario']?.toString() ?? '';
          _jaTemAvaliacao = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar avaliação existente: $e');
    } finally {
      if (mounted) {
        setState(() => _carregandoDados = false);
      }
    }
  }

  Future<void> _salvarAvaliacao() async {
    setState(() => _enviando = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw "Usuário não autenticado.";
      }

      // Upsert atualiza se já existir ou insere se não existir (baseado em prestador_id, cliente_id)
      await Supabase.instance.client.from('tab_avaliacoes').upsert({
        'prestador_id': widget.prestadorId,
        'cliente_id': user.id,
        'nota': _notaSelecionada,
        'comentario': _comentarioController.text.trim().isEmpty
            ? null
            : _comentarioController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'prestador_id,cliente_id');

      if (!mounted) return;
      Navigator.pop(
          context, true); // Retorna sucesso para atualizar a tela anterior
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_jaTemAvaliacao
              ? 'Avaliação atualizada com sucesso!'
              : 'Avaliação enviada com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar avaliação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF101B2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _carregandoDados
          ? const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _jaTemAvaliacao
                      ? 'Editar sua Avaliação'
                      : 'Avaliar Profissional',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Estrelas Interativas
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    int starValue = index + 1;
                    return IconButton(
                      icon: Icon(
                        starValue <= _notaSelecionada
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () {
                        setState(() {
                          _notaSelecionada = starValue;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Comentários ofensivos e sem provas para prejudicar usuários geram banimento permanente.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _comentarioController,
                  maxLength: 200,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Escreva um comentário (opcional)...',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFFF8C00))),
                  ),
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _enviando ? null : _salvarAvaliacao,
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _jaTemAvaliacao
                              ? 'Atualizar Avaliação'
                              : 'Enviar Avaliação',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                ),
              ],
            ),
    );
  }
}
