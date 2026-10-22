import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================

// TELA 1: DETALHES DA CAMPANHA, PRÊMIO, CÓDIGO E PONTUAÇÃO

// ============================================================================

class DetalhesCampanhaPage extends StatefulWidget {
  const DetalhesCampanhaPage({super.key});

  @override
  State<DetalhesCampanhaPage> createState() => _DetalhesCampanhaPageState();
}

class _DetalhesCampanhaPageState extends State<DetalhesCampanhaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, dynamic>? campanhaAtiva;

  String meuCodigo = '';

  int meusPontos = 0;

  int minhasIndicacoesValidas = 0;

  bool _carregando = true;

  String? _erro;

  String get meuId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();

    _carregarDadosCampanha();
  }

  DateTime? _converterData(dynamic valor) {
    if (valor == null) return null;

    return DateTime.tryParse(valor.toString());
  }

  bool _campanhaDentroDoPeriodo(Map<String, dynamic> campanha) {
    final agora = DateTime.now();

    final inicio = _converterData(campanha['data_inicio']);

    final fim = _converterData(campanha['data_fim']);

    if (inicio != null && agora.isBefore(inicio)) return false;

    if (fim != null && agora.isAfter(fim)) return false;

    return true;
  }

  bool _campanhaAtendeLocalizacao(
    Map<String, dynamic> campanha,
    String cidade,
    String estado,
  ) {
    final tipoAlcance =
        (campanha['tipo_alcance'] ?? 'brasil').toString().trim().toLowerCase();

    if (tipoAlcance == 'brasil') return true;

    if (tipoAlcance == 'estados') {
      final estados = campanha['estados_alvo'];

      if (estados is! List) return false;

      return estados.any(
        (e) => e.toString().trim().toUpperCase() == estado.toUpperCase(),
      );
    }

    if (tipoAlcance == 'cidades') {
      final cidades = campanha['cidades_alvo'];

      if (cidades is! List) return false;

      final cidadeNormalizada = cidade.trim().toLowerCase();

      if (cidadeNormalizada.isEmpty) return false;

      return cidades.any((c) {
        final alvo = c.toString().trim().toLowerCase();

        return alvo == cidadeNormalizada ||
            alvo.contains(cidadeNormalizada) ||
            cidadeNormalizada.contains(alvo);
      });
    }

    return false;
  }

  Future<void> _carregarDadosCampanha() async {
    if (mounted) {
      setState(() {
        _carregando = true;

        _erro = null;
      });
    }

    try {
      if (meuId.isEmpty) {
        throw Exception('Usuário não autenticado.');
      }

      // 1. Busca somente os dados necessários para o filtro geográfico.

      final dynamic resUsuario = await _supabase
          .from('tab_usuarios')
          .select('cidade, estado')
          .eq('id', meuId)
          .maybeSingle();

      final usuario = resUsuario == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(resUsuario as Map);

      final minhaCidade =
          (usuario['cidade'] ?? '').toString().trim().toLowerCase();

      final meuEstado =
          (usuario['estado'] ?? '').toString().trim().toUpperCase();

      // 2. Busca campanhas marcadas como ativas.

      final dynamic respostaCampanhas = await _supabase
          .from('tab_campanhas')
          .select()
          .eq('ativa', true)
          .order('data_inicio', ascending: false);

      final campanhas = (respostaCampanhas as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_campanhaDentroDoPeriodo)
          .toList();

      Map<String, dynamic>? encontrada;

      // Prioriza campanha específica da cidade.

      for (final campanha in campanhas) {
        final tipo = (campanha['tipo_alcance'] ?? 'brasil')
            .toString()
            .trim()
            .toLowerCase();

        if (tipo == 'cidades' &&
            _campanhaAtendeLocalizacao(campanha, minhaCidade, meuEstado)) {
          encontrada = campanha;

          break;
        }
      }

      // Depois campanha por estado.

      encontrada ??= campanhas.cast<Map<String, dynamic>?>().firstWhere(
        (campanha) {
          if (campanha == null) return false;

          final tipo = (campanha['tipo_alcance'] ?? 'brasil')
              .toString()
              .trim()
              .toLowerCase();

          return tipo == 'estados' &&
              _campanhaAtendeLocalizacao(
                campanha,
                minhaCidade,
                meuEstado,
              );
        },
        orElse: () => null,
      );

      // Por último campanha nacional.

      encontrada ??= campanhas.cast<Map<String, dynamic>?>().firstWhere(
        (campanha) {
          if (campanha == null) return false;

          return (campanha['tipo_alcance'] ?? 'brasil')
                  .toString()
                  .trim()
                  .toLowerCase() ==
              'brasil';
        },
        orElse: () => null,
      );

      // Compatibilidade com campanhas antigas sem alcance corretamente definido.

      if (encontrada == null && campanhas.isNotEmpty) {
        encontrada = campanhas.firstWhere(
          (campanha) =>
              _campanhaAtendeLocalizacao(campanha, minhaCidade, meuEstado),
          orElse: () => campanhas.first,
        );
      }

      if (encontrada == null) {
        if (!mounted) return;

        setState(() {
          campanhaAtiva = null;

          meuCodigo = '';

          meusPontos = 0;

          minhasIndicacoesValidas = 0;

          _carregando = false;
        });

        return;
      }

      final campanhaId = encontrada['id'];

      if (campanhaId == null) {
        throw Exception('A campanha ativa não possui um ID válido.');
      }

      // 3. A RPC segura cria a participação se necessário ou devolve a existente.

      // Ela usa auth.uid() no servidor, portanto o app não escolhe o usuario_id.

      final dynamic respostaParticipacao = await _supabase.rpc(
        'participar_campanha',
        params: {'p_campanha_id': campanhaId},
      );

      Map<String, dynamic>? participacao;

      if (respostaParticipacao is List && respostaParticipacao.isNotEmpty) {
        participacao = Map<String, dynamic>.from(
          respostaParticipacao.first as Map,
        );
      } else if (respostaParticipacao is Map) {
        participacao = Map<String, dynamic>.from(respostaParticipacao);
      }

      if (participacao == null) {
        throw Exception('Não foi possível obter a participação na campanha.');
      }

      if (!mounted) return;

      setState(() {
        campanhaAtiva = encontrada;

        meuCodigo = (participacao!['codigo_indicacao'] ?? '').toString();

        meusPontos = _paraInt(participacao['total_pontos']);

        minhasIndicacoesValidas =
            _paraInt(participacao['total_indicacoes_validas']);

        _carregando = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Erro ao carregar detalhes da campanha: $e');

      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _erro = e.toString();

        _carregando = false;
      });
    }
  }

  int _paraInt(dynamic valor) {
    if (valor == null) return 0;

    if (valor is int) return valor;

    if (valor is num) return valor.toInt();

    return int.tryParse(valor.toString()) ?? 0;
  }

  void _abrirRanking() {
    final campanha = campanhaAtiva;

    if (campanha == null || campanha['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma campanha ativa disponível para o ranking.'),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RankingCampanhaPage(
          campanhaId: _paraInt(campanha['id']),
          tituloCampanha: (campanha['titulo'] ?? 'Campanha').toString(),
        ),
      ),
    );
  }

  String _limparMarcacaoRegras(String texto) {
    return texto.replaceAll('**', '').replaceAll('---', '').trim();
  }

  void _compartilharApp() {
    if (campanhaAtiva == null || meuCodigo.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde o carregamento da sua participação.'),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    const linkGooglePlay =
        'https://play.google.com/store/apps/details?id=br.com.acheobra.app';

    const mensagem = '🚀 Conheça o Ache Obra!\n\n'
        '🏗️ Encontre profissionais, serviços e oportunidades para sua obra em um só lugar.\n\n'
        '📲 Baixe o Ache Obra gratuitamente na Google Play:\n'
        '$linkGooglePlay\n\n'
        '🎁 Cadastre-se, aproveite os recursos do aplicativo e participe das campanhas e promoções disponíveis.\n\n'
        'Ache Obra — conectando quem precisa com quem sabe fazer! 🛠️';

    Share.share(mensagem);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text(
          'Concorra ao Prêmio',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events, color: Color(0xFFFF8C00)),
            tooltip: 'Ver Ranking',
            onPressed: campanhaAtiva == null ? null : _abrirRanking,
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
            )
          : RefreshIndicator(
              onRefresh: _carregarDadosCampanha,
              color: const Color(0xFFFF8C00),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF101B2B),
                        disabledBackgroundColor: const Color(0xFF101B2B),
                        side: BorderSide(
                          color: campanhaAtiva == null
                              ? Colors.white24
                              : const Color(0xFFFF8C00),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: campanhaAtiva == null ? null : _abrirRanking,
                      icon: Icon(
                        Icons.emoji_events,
                        color: campanhaAtiva == null
                            ? Colors.white38
                            : const Color(0xFFFF8C00),
                      ),
                      label: Text(
                        'Ver Ranking da Competição',
                        style: TextStyle(
                          color: campanhaAtiva == null
                              ? Colors.white38
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_erro != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Não foi possível carregar todos os dados da campanha.',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _erro!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: _carregarDadosCampanha,
                              icon: const Icon(
                                Icons.refresh,
                                color: Color(0xFFFF8C00),
                              ),
                              label: const Text(
                                'Tentar novamente',
                                style: TextStyle(color: Color(0xFFFF8C00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (campanhaAtiva != null) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B2B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if ((campanhaAtiva!['imagem_url'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  minHeight: 180,
                                  maxHeight: 360,
                                ),
                                color: Colors.black,
                                alignment: Alignment.center,
                                child: Image.network(
                                  campanhaAtiva!['imagem_url'].toString(),
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 180,
                                      width: double.infinity,
                                      color: const Color(0xFF1A2C42),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported_outlined,
                                        color: Colors.white38,
                                        size: 42,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    campanhaAtiva!['titulo'] ??
                                        'Campanha Ativa',
                                    style: const TextStyle(
                                      color: Color(0xFFFF8C00),
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '🎁 Prêmio: ${campanhaAtiva!['descricao_premio'] ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A2C42),
                                        borderRadius: BorderRadius.circular(10),
                                        border:
                                            Border.all(color: Colors.white12),
                                      ),
                                      child: ExpansionTile(
                                        iconColor: const Color(0xFFFF8C00),
                                        collapsedIconColor:
                                            const Color(0xFFFF8C00),
                                        title: const Text(
                                          'Ver Regras da Campanha',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        childrenPadding:
                                            const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          16,
                                        ),
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _limparMarcacaoRegras(
                                                (campanhaAtiva!['regras'] ?? '')
                                                    .toString(),
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                height: 1.45,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_erro == null) ...[
                      Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B2B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'Nenhuma campanha ativa para a sua região no momento.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (campanhaAtiva != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B2B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Seu Código de Indicação',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2C42),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFF8C00),
                                ),
                              ),
                              child: Text(
                                meuCodigo.isEmpty ? '---' : meuCodigo,
                                style: const TextStyle(
                                  color: Color(0xFFFF8C00),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Pontuação atual: $meusPontos pontos',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$minhasIndicacoesValidas indicações válidas',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF8C00),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              onPressed:
                                  meuCodigo.isEmpty ? null : _compartilharApp,
                              icon:
                                  const Icon(Icons.share, color: Colors.white),
                              label: const Text(
                                'Indicar Amigos e Ganhar Pontos',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ============================================================================

// TELA 2: RANKING DA CAMPANHA (TOP 20 + POSIÇÃO DO USUÁRIO)

// ============================================================================

class RankingCampanhaPage extends StatefulWidget {
  final int campanhaId;

  final String tituloCampanha;

  const RankingCampanhaPage({
    super.key,
    required this.campanhaId,
    required this.tituloCampanha,
  });

  @override
  State<RankingCampanhaPage> createState() => _RankingCampanhaPageState();
}

class _RankingCampanhaPageState extends State<RankingCampanhaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _carregando = true;

  String? _erro;

  List<Map<String, dynamic>> _ranking = [];

  String get meuId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();

    _carregarRanking();
  }

  int _paraInt(dynamic valor) {
    if (valor == null) return 0;

    if (valor is int) return valor;

    if (valor is num) return valor.toInt();

    return int.tryParse(valor.toString()) ?? 0;
  }

  Future<void> _carregarRanking() async {
    if (mounted) {
      setState(() {
        _carregando = true;

        _erro = null;
      });
    }

    try {
      final dynamic resposta = await _supabase
          .from('vw_campanhas_ranking')
          .select()
          .eq('campanha_id', widget.campanhaId)
          .order('posicao_ranking', ascending: true);

      final ranking = (resposta as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;

      setState(() {
        _ranking = ranking;

        _carregando = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Erro ao carregar ranking da campanha: $e');

      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _erro = e.toString();

        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text(
          'Ranking da Competição',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregarRanking,
            tooltip: 'Atualizar ranking',
            icon: const Icon(Icons.refresh, color: Color(0xFFFF8C00)),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
            )
          : _erro != null
              ? _buildErro()
              : _buildRanking(),
    );
  }

  Widget _buildErro() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 52,
            ),
            const SizedBox(height: 14),
            const Text(
              'Não foi possível carregar o ranking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _carregarRanking,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
              ),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRanking() {
    if (_ranking.isEmpty) {
      return RefreshIndicator(
        onRefresh: _carregarRanking,
        color: const Color(0xFFFF8C00),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            const Icon(
              Icons.emoji_events_outlined,
              color: Colors.white38,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              widget.tituloCampanha,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFF8C00),
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nenhum participante no ranking ainda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final top20 = _ranking.take(20).toList();

    Map<String, dynamic>? meuPerfil;

    for (final registro in _ranking) {
      if ((registro['usuario_id'] ?? '').toString() == meuId) {
        meuPerfil = registro;

        break;
      }
    }

    final minhaPosicao =
        meuPerfil == null ? -1 : _paraInt(meuPerfil['posicao_ranking']);

    final estouNoTop20 = minhaPosicao > 0 && minhaPosicao <= 20;

    return RefreshIndicator(
      onRefresh: _carregarRanking,
      color: const Color(0xFFFF8C00),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🏆 Top 20 Participantes',
              style: TextStyle(
                color: Color(0xFFFF8C00),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.tituloCampanha,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Veja quem está liderando a disputa pelos prêmios.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: top20.length,
              itemBuilder: (context, index) {
                return _buildParticipante(top20[index]);
              },
            ),
            if (!estouNoTop20 && meuPerfil != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '. . .',
                    style: TextStyle(color: Colors.white54, fontSize: 22),
                  ),
                ),
              ),
              const Text(
                'Sua Posição:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildParticipante(meuPerfil, destacar: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParticipante(
    Map<String, dynamic> participante, {
    bool destacar = false,
  }) {
    final posicao = _paraInt(participante['posicao_ranking']);

    final nome = (participante['usuario_nome'] ?? 'Participante').toString();

    final pontos = _paraInt(participante['total_pontos']);

    final indicacoes = _paraInt(participante['total_indicacoes_validas']);

    final eMeuUsuario = (participante['usuario_id'] ?? '').toString() == meuId;

    Color corBadge = const Color(0xFF101B2B);

    if (posicao == 1) corBadge = Colors.amber;

    if (posicao == 2) corBadge = Colors.grey.shade400;

    if (posicao == 3) corBadge = Colors.brown.shade400;

    final realcar = destacar || eMeuUsuario;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: realcar
            ? const Color(0xFFFF8C00).withOpacity(0.20)
            : const Color(0xFF101B2B),
        borderRadius: BorderRadius.circular(8),
        border: realcar
            ? Border.all(color: const Color(0xFFFF8C00))
            : Border.all(color: Colors.white12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: corBadge,
          child: Text(
            '$posicaoº',
            style: TextStyle(
              color: posicao <= 3 ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          nome,
          style: TextStyle(
            color: Colors.white,
            fontWeight: realcar ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        subtitle: indicacoes > 0
            ? Text(
                '$indicacoes ${indicacoes == 1 ? 'indicação válida' : 'indicações válidas'}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              )
            : null,
        trailing: Text(
          '$pontos pts',
          style: const TextStyle(
            color: Color(0xFFFF8C00),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
