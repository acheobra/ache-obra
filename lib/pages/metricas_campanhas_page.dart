import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasCampanhasPage extends StatefulWidget {
  const MetricasCampanhasPage({super.key});

  @override
  State<MetricasCampanhasPage> createState() => _MetricasCampanhasPageState();
}

class _MetricasCampanhasPageState extends State<MetricasCampanhasPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _fundoEscuro = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);

  bool _carregando = true;
  String? _erro;

  DateTime _inicio = DateTime(DateTime.now().year, 1, 1);
  DateTime _fim = DateTime.now();

  List<Map<String, dynamic>> _campanhas = [];
  List<Map<String, dynamic>> _participantes = [];
  List<Map<String, dynamic>> _indicacoes = [];
  List<Map<String, dynamic>> _ranking = [];
  List<Map<String, dynamic>> _usuarios = [];

  int? _campanhaSelecionada;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  int _int(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  DateTime? _data(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  String _normalizar(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  bool _noPeriodo(DateTime? data) {
    if (data == null) return false;
    final ini = DateTime(_inicio.year, _inicio.month, _inicio.day);
    final fim = DateTime(_fim.year, _fim.month, _fim.day, 23, 59, 59, 999);
    return !data.isBefore(ini) && !data.isAfter(fim);
  }

  bool _naCampanha(Map<String, dynamic> item) {
    if (_campanhaSelecionada == null) return true;
    return _int(item['campanha_id']) == _campanhaSelecionada;
  }

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _supabase
            .from('tab_campanhas')
            .select()
            .order('data_inicio', ascending: false),
        _supabase
            .from('tab_campanhas_participantes')
            .select()
            .order('data_entrada', ascending: false),
        _supabase
            .from('tab_campanhas_indicacoes')
            .select()
            .order('data_indicacao', ascending: false),
        _supabase
            .from('vw_campanhas_ranking')
            .select()
            .order('posicao_ranking', ascending: true),
        _supabase.from('tab_usuarios').select(
            'id, usuario_nome, cidade, estado, usuario_tipo, nome_plano_ativo, dt_cadastro, genero, dt_nascimento, recorrente, usuario_status'),
      ]);

      if (!mounted) return;

      setState(() {
        _campanhas = (resultados[0] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _participantes = (resultados[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _indicacoes = (resultados[2] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _ranking = (resultados[3] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _usuarios = (resultados[4] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _carregando = false;
      });
    } catch (e, st) {
      debugPrint('Erro em métricas de campanhas: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _participantesFiltrados => _participantes
      .where(_naCampanha)
      .where((e) => _noPeriodo(_data(e['data_entrada'])))
      .toList();

  List<Map<String, dynamic>> get _indicacoesFiltradas => _indicacoes
      .where(_naCampanha)
      .where((e) => _noPeriodo(_data(e['data_indicacao'])))
      .toList();

  List<Map<String, dynamic>> get _rankingFiltrado =>
      _ranking.where(_naCampanha).toList();

  List<Map<String, dynamic>> get _indicacoesValidas => _indicacoesFiltradas
      .where((e) => _normalizar(e['status']) == 'valida')
      .toList();

  List<Map<String, dynamic>> get _indicacoesInvalidas => _indicacoesFiltradas
      .where((e) => _normalizar(e['status']) != 'valida')
      .toList();

  Map<String, dynamic>? _usuario(String id) {
    for (final u in _usuarios) {
      if ((u['id'] ?? '').toString() == id) return u;
    }
    return null;
  }

  String _tituloCampanha(int id) {
    for (final c in _campanhas) {
      if (_int(c['id']) == id) {
        return (c['titulo'] ?? 'Campanha $id').toString();
      }
    }
    return 'Campanha $id';
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtPct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  Future<void> _selecionarInicio() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _inicio,
      titulo: 'Data inicial',
    );
    if (d != null && mounted) {
      setState(() {
        _inicio = d;
        if (_fim.isBefore(_inicio)) _fim = _inicio;
      });
    }
  }

  Future<void> _selecionarFim() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _fim,
      titulo: 'Data final',
    );
    if (d != null && mounted) {
      setState(() {
        _fim = d;
        if (_inicio.isAfter(_fim)) _inicio = _fim;
      });
    }
  }

  void _atalho(int dias) {
    final agora = DateTime.now();
    setState(() {
      _fim = agora;
      _inicio = DateTime(agora.year, agora.month, agora.day)
          .subtract(Duration(days: dias - 1));
    });
  }

  void _todoPeriodo() {
    DateTime? menor;
    DateTime? maior;

    for (final p in _participantes) {
      final d = _data(p['data_entrada']);
      if (d != null) {
        if (menor == null || d.isBefore(menor)) menor = d;
        if (maior == null || d.isAfter(maior)) maior = d;
      }
    }
    for (final i in _indicacoes) {
      final d = _data(i['data_indicacao']);
      if (d != null) {
        if (menor == null || d.isBefore(menor)) menor = d;
        if (maior == null || d.isAfter(maior)) maior = d;
      }
    }
    for (final c in _campanhas) {
      final d = _data(c['data_inicio']);
      if (d != null) {
        if (menor == null || d.isBefore(menor)) menor = d;
        if (maior == null || d.isAfter(maior)) maior = d;
      }
    }

    if (menor != null && maior != null) {
      setState(() {
        _inicio = menor!;
        _fim = DateTime.now().isAfter(maior!) ? DateTime.now() : maior!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundoEscuro,
        foregroundColor: Colors.white,
        title: const Text('Métricas • Campanhas'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarDados,
            icon: const Icon(Icons.refresh, color: _laranja),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : _erro != null
              ? _buildErro()
              : RefreshIndicator(
                  onRefresh: _carregarDados,
                  color: _laranja,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildFiltros(),
                      const SizedBox(height: 16),
                      _buildResumoPrincipal(),
                      const SizedBox(height: 16),
                      _buildConversao(),
                      const SizedBox(height: 16),
                      _buildCampanhas(),
                      const SizedBox(height: 16),
                      _buildEvolucao(),
                      const SizedBox(height: 16),
                      _buildRanking(),
                      const SizedBox(height: 16),
                      _buildPerfilIndicados(),
                      const SizedBox(height: 16),
                      _buildGeografia(),
                      const SizedBox(height: 16),
                      _buildQualidade(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar as métricas de campanhas.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _carregarDados,
              style: ElevatedButton.styleFrom(backgroundColor: _laranja),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Tentar novamente',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return _secao(
      titulo: 'Período e campanha',
      icone: Icons.tune,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      _botaoData('Data inicial', _inicio, _selecionarInicio)),
              const SizedBox(width: 10),
              Expanded(child: _botaoData('Data final', _fim, _selecionarFim)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _campanhaSelecionada,
            dropdownColor: _fundoEscuro,
            decoration: _inputDecoration('Campanha'),
            style: const TextStyle(color: Colors.white),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Todas as campanhas'),
              ),
              ..._campanhas.map(
                (c) => DropdownMenuItem<int?>(
                  value: _int(c['id']),
                  child: Text(
                    (c['titulo'] ?? 'Campanha ${c['id']}').toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _campanhaSelecionada = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipPeriodo('7 dias', () => _atalho(7)),
              _chipPeriodo('30 dias', () => _atalho(30)),
              _chipPeriodo('90 dias', () => _atalho(90)),
              _chipPeriodo('1 ano', () => _atalho(365)),
              _chipPeriodo('Todo período', _todoPeriodo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumoPrincipal() {
    final participantes = _participantesFiltrados;
    final validas = _indicacoesValidas;
    final invalidas = _indicacoesInvalidas;

    final participantesUnicos =
        participantes.map((e) => e['usuario_id'].toString()).toSet().length;
    final conquistados =
        validas.map((e) => e['indicado_id'].toString()).toSet().length;
    final indicadores =
        validas.map((e) => e['indicante_id'].toString()).toSet().length;
    final pontos = validas.fold<int>(0, (s, e) => s + _int(e['pontos']));
    final ativos = participantes
        .where((e) => e['ativo'] == true && e['desclassificado'] != true)
        .length;
    final desclassificados =
        participantes.where((e) => e['desclassificado'] == true).length;

    return _secao(
      titulo: 'Visão geral',
      icone: Icons.campaign,
      child: _grade([
        _metrica('Participantes', '$participantesUnicos', Icons.groups),
        _metrica('Participações ativas', '$ativos', Icons.how_to_reg),
        _metrica('Usuários que indicaram', '$indicadores', Icons.share),
        _metrica(
            'Usuários conquistados', '$conquistados', Icons.person_add_alt_1),
        _metrica('Indicações válidas', '${validas.length}', Icons.check_circle),
        _metrica('Indicações não válidas', '${invalidas.length}', Icons.cancel),
        _metrica('Pontos distribuídos', '$pontos', Icons.stars),
        _metrica('Desclassificados', '$desclassificados', Icons.block),
      ]),
    );
  }

  Widget _buildConversao() {
    final participantes =
        _participantesFiltrados.map((e) => e['usuario_id'].toString()).toSet();
    final indicantes =
        _indicacoesValidas.map((e) => e['indicante_id'].toString()).toSet();
    final conquistados =
        _indicacoesValidas.map((e) => e['indicado_id'].toString()).toSet();

    final taxaAtivacao = participantes.isEmpty
        ? 0.0
        : indicantes.length / participantes.length * 100;
    final media = participantes.isEmpty
        ? 0.0
        : _indicacoesValidas.length / participantes.length;
    final taxaValidade = _indicacoesFiltradas.isEmpty
        ? 0.0
        : _indicacoesValidas.length / _indicacoesFiltradas.length * 100;

    return _secao(
      titulo: 'Conversão das indicações',
      icone: Icons.trending_up,
      child: Column(
        children: [
          _linhaIndicador(
            'Participante → fez ao menos 1 indicação válida',
            _fmtPct(taxaAtivacao),
          ),
          _linhaIndicador(
            'Média de indicações válidas por participante',
            media.toStringAsFixed(2).replaceAll('.', ','),
          ),
          _linhaIndicador(
            'Taxa de validade das indicações registradas',
            _fmtPct(taxaValidade),
          ),
          _linhaIndicador(
            'Novos usuários atribuídos às campanhas',
            '${conquistados.length}',
          ),
          const SizedBox(height: 10),
          const Text(
            'As conversões acima usam somente registros existentes em '
            'tab_campanhas_indicacoes. Cliques ou instalações sem atribuição '
            'registrada não entram nesses cálculos.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildCampanhas() {
    final linhas = <Map<String, dynamic>>[];

    for (final c in _campanhas) {
      final id = _int(c['id']);
      if (_campanhaSelecionada != null && id != _campanhaSelecionada) continue;

      final parts = _participantesFiltrados
          .where((e) => _int(e['campanha_id']) == id)
          .toList();
      final inds = _indicacoesFiltradas
          .where((e) => _int(e['campanha_id']) == id)
          .toList();
      final validas =
          inds.where((e) => _normalizar(e['status']) == 'valida').toList();

      linhas.add({
        'id': id,
        'titulo': c['titulo'],
        'ativa': c['ativa'] == true,
        'premio': c['descricao_premio'],
        'alcance': c['tipo_alcance'],
        'participantes':
            parts.map((e) => e['usuario_id'].toString()).toSet().length,
        'validas': validas.length,
        'conquistados':
            validas.map((e) => e['indicado_id'].toString()).toSet().length,
        'pontos': validas.fold<int>(0, (s, e) => s + _int(e['pontos'])),
      });
    }

    return _secao(
      titulo: 'Desempenho por campanha',
      icone: Icons.emoji_events,
      child: linhas.isEmpty
          ? _vazio('Nenhuma campanha encontrada para o filtro atual.')
          : Column(
              children: linhas.map((e) {
                return _cardLista(
                  titulo: (e['titulo'] ?? 'Campanha').toString(),
                  subtitulo:
                      '${e['ativa'] ? 'Ativa' : 'Inativa'} • ${e['alcance'] ?? 'alcance não informado'}'
                      '${(e['premio'] ?? '').toString().trim().isEmpty ? '' : '\nPrêmio: ${e['premio']}'}',
                  direita:
                      '${e['participantes']} participantes\n${e['conquistados']} conquistados',
                  rodape:
                      '${e['validas']} indicações válidas • ${e['pontos']} pontos',
                );
              }).toList(),
            ),
    );
  }

  Widget _buildEvolucao() {
    final mapa = <DateTime, Map<String, int>>{};

    for (final i in _indicacoesFiltradas) {
      final d = _data(i['data_indicacao']);
      if (d == null) continue;
      final dia = DateTime(d.year, d.month, d.day);
      final item = mapa.putIfAbsent(
        dia,
        () => {'total': 0, 'validas': 0, 'pontos': 0},
      );
      item['total'] = item['total']! + 1;
      if (_normalizar(i['status']) == 'valida') {
        item['validas'] = item['validas']! + 1;
        item['pontos'] = item['pontos']! + _int(i['pontos']);
      }
    }

    final dias = mapa.keys.toList()..sort((a, b) => b.compareTo(a));

    return _secao(
      titulo: 'Evolução das indicações',
      icone: Icons.timeline,
      child: dias.isEmpty
          ? _vazio('Ainda não existem indicações no período selecionado.')
          : Column(
              children: dias.take(30).map((d) {
                final x = mapa[d]!;
                return _linhaIndicador(
                  _fmtData(d),
                  '${x['validas']} válidas / ${x['total']} total • ${x['pontos']} pts',
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRanking() {
    final mapa = <String, Map<String, dynamic>>{};

    for (final i in _indicacoesValidas) {
      final id = (i['indicante_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final x = mapa.putIfAbsent(
        id,
        () => {'usuario_id': id, 'validas': 0, 'pontos': 0},
      );
      x['validas'] = _int(x['validas']) + 1;
      x['pontos'] = _int(x['pontos']) + _int(i['pontos']);
    }

    // Se ainda não houver indicação no período, mantém visibilidade do ranking
    // geral da campanha, mas sem misturá-lo aos totais filtrados por data.
    final lista = mapa.values.toList()
      ..sort((a, b) {
        final p = _int(b['pontos']).compareTo(_int(a['pontos']));
        if (p != 0) return p;
        return _int(b['validas']).compareTo(_int(a['validas']));
      });

    return _secao(
      titulo: 'Ranking de indicadores no período',
      icone: Icons.leaderboard,
      child: lista.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _vazio('Nenhuma indicação válida no período selecionado.'),
                if (_rankingFiltrado.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Ranking geral atual',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._rankingFiltrado.take(10).map(
                        (r) => _cardLista(
                          titulo:
                              '${_int(r['posicao_ranking'])}º • ${(r['usuario_nome'] ?? 'Participante')}',
                          subtitulo:
                              '${r['cidade'] ?? '-'} / ${r['estado'] ?? '-'} • ${r['usuario_tipo'] ?? '-'}',
                          direita: '${_int(r['total_pontos'])} pts',
                          rodape:
                              '${_int(r['total_indicacoes_validas'])} indicações válidas',
                        ),
                      ),
                ],
              ],
            )
          : Column(
              children:
                  List.generate(lista.length > 20 ? 20 : lista.length, (idx) {
                final r = lista[idx];
                final u = _usuario(r['usuario_id'].toString());
                return _cardLista(
                  titulo:
                      '${idx + 1}º • ${(u?['usuario_nome'] ?? 'Participante')}',
                  subtitulo:
                      '${u?['cidade'] ?? '-'} / ${u?['estado'] ?? '-'} • ${u?['usuario_tipo'] ?? '-'}',
                  direita: '${_int(r['pontos'])} pts',
                  rodape: '${_int(r['validas'])} indicações válidas',
                );
              }),
            ),
    );
  }

  Widget _buildPerfilIndicados() {
    final ids =
        _indicacoesValidas.map((e) => e['indicado_id'].toString()).toSet();

    final tipos = <String, int>{};
    final planos = <String, int>{};
    final generos = <String, int>{};
    int recorrentes = 0;

    for (final id in ids) {
      final u = _usuario(id);
      if (u == null) continue;

      final tipo = (u['usuario_tipo'] ?? 'Não informado').toString().trim();
      final plano = (u['nome_plano_ativo'] ?? 'Sem plano').toString().trim();
      final genero = (u['genero'] ?? 'Não informado').toString().trim();

      tipos[tipo.isEmpty ? 'Não informado' : tipo] =
          (tipos[tipo.isEmpty ? 'Não informado' : tipo] ?? 0) + 1;
      planos[plano.isEmpty ? 'Sem plano' : plano] =
          (planos[plano.isEmpty ? 'Sem plano' : plano] ?? 0) + 1;
      generos[genero.isEmpty ? 'Não informado' : genero] =
          (generos[genero.isEmpty ? 'Não informado' : genero] ?? 0) + 1;
      if (u['recorrente'] == true) recorrentes++;
    }

    return _secao(
      titulo: 'Perfil dos usuários conquistados',
      icone: Icons.person_search,
      child: ids.isEmpty
          ? _vazio('Ainda não há usuários conquistados por indicação.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _subtitulo('Por tipo de usuário'),
                ..._ordenarMapa(tipos).map(
                  (e) => _linhaIndicador(e.key, '${e.value}'),
                ),
                const SizedBox(height: 12),
                _subtitulo('Por plano atual'),
                ..._ordenarMapa(planos).map(
                  (e) => _linhaIndicador(e.key, '${e.value}'),
                ),
                const SizedBox(height: 12),
                _subtitulo('Por gênero'),
                ..._ordenarMapa(generos).map(
                  (e) => _linhaIndicador(e.key, '${e.value}'),
                ),
                const SizedBox(height: 12),
                _linhaIndicador('Com recorrência ativa', '$recorrentes'),
              ],
            ),
    );
  }

  Widget _buildGeografia() {
    final ids =
        _indicacoesValidas.map((e) => e['indicado_id'].toString()).toSet();
    final estados = <String, int>{};
    final cidades = <String, int>{};

    for (final id in ids) {
      final u = _usuario(id);
      if (u == null) continue;
      final estado = (u['estado'] ?? 'Não informado').toString().trim();
      final cidade = (u['cidade'] ?? 'Não informado').toString().trim();
      final uf = estado.isEmpty ? 'Não informado' : estado;
      final cid = cidade.isEmpty ? 'Não informado' : cidade;
      estados[uf] = (estados[uf] ?? 0) + 1;
      cidades['$cid / $uf'] = (cidades['$cid / $uf'] ?? 0) + 1;
    }

    return _secao(
      titulo: 'Geografia dos usuários conquistados',
      icone: Icons.public,
      child: ids.isEmpty
          ? _vazio('Ainda não há dados geográficos de usuários indicados.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _subtitulo('Estados'),
                ..._ordenarMapa(estados).take(15).map(
                      (e) => _linhaIndicador(e.key, '${e.value}'),
                    ),
                const SizedBox(height: 12),
                _subtitulo('Cidades'),
                ..._ordenarMapa(cidades).take(20).map(
                      (e) => _linhaIndicador(e.key, '${e.value}'),
                    ),
              ],
            ),
    );
  }

  Widget _buildQualidade() {
    final total = _indicacoesFiltradas.length;
    final validas = _indicacoesValidas.length;
    final invalidas = _indicacoesInvalidas.length;
    final participantes = _participantesFiltrados.length;
    final desclassificados = _participantesFiltrados
        .where((e) => e['desclassificado'] == true)
        .length;

    final taxaInvalidacao = total == 0 ? 0.0 : invalidas / total * 100;
    final taxaDesclassificacao =
        participantes == 0 ? 0.0 : desclassificados / participantes * 100;

    final status = <String, int>{};
    for (final i in _indicacoesFiltradas) {
      final s = (i['status'] ?? 'Não informado').toString();
      status[s] = (status[s] ?? 0) + 1;
    }

    return _secao(
      titulo: 'Qualidade e controle',
      icone: Icons.verified_user,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _linhaIndicador('Registros de indicação', '$total'),
          _linhaIndicador('Válidas', '$validas'),
          _linhaIndicador('Não válidas', '$invalidas'),
          _linhaIndicador('Taxa de não validade', _fmtPct(taxaInvalidacao)),
          _linhaIndicador(
              'Taxa de desclassificação', _fmtPct(taxaDesclassificacao)),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 12),
            _subtitulo('Status encontrados'),
            ..._ordenarMapa(status)
                .map((e) => _linhaIndicador(e.key, '${e.value}')),
          ],
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _ordenarMapa(Map<String, int> mapa) {
    final lista = mapa.entries.toList();
    lista.sort((a, b) => b.value.compareTo(a.value));
    return lista;
  }

  Widget _secao({
    required String titulo,
    required IconData icone,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundoEscuro,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, color: _laranja),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _grade(List<Widget> itens) {
    return LayoutBuilder(
      builder: (context, c) {
        final largura = c.maxWidth;
        final colunas = largura >= 900
            ? 4
            : largura >= 560
                ? 3
                : 2;
        final espaco = 10.0;
        final larguraItem = (largura - (espaco * (colunas - 1))) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children:
              itens.map((e) => SizedBox(width: larguraItem, child: e)).toList(),
        );
      },
    );
  }

  Widget _metrica(String titulo, String valor, IconData icone) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: _laranja, size: 20),
          const Spacer(),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            titulo,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _botaoData(String label, DateTime data, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: _fundo,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_month, color: _laranja, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _fmtData(data),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipPeriodo(String texto, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: _fundo,
      side: const BorderSide(color: Colors.white12),
      label: Text(texto, style: const TextStyle(color: Colors.white70)),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: _fundo,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _laranja),
      ),
    );
  }

  Widget _linhaIndicador(String nome, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              nome,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            valor,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        color: _laranja,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _cardLista({
    required String titulo,
    required String subtitulo,
    required String direita,
    required String rodape,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                direita,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _laranja,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitulo,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            rodape,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _vazio(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 13),
      ),
    );
  }
}
