import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasRetencaoPage extends StatefulWidget {
  const MetricasRetencaoPage({super.key});

  @override
  State<MetricasRetencaoPage> createState() => _MetricasRetencaoPageState();
}

class _MetricasRetencaoPageState extends State<MetricasRetencaoPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _fundoEscuro = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);
  static const Color _card = Color(0xFF142338);

  bool _carregando = true;
  String? _erro;
  DateTime _inicio = DateTime(DateTime.now().year, 1, 1);
  DateTime _fim = DateTime.now();

  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _acessos = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  DateTime? _data(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  String _norm(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtPct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  String _fmtNum(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  bool _noPeriodo(DateTime? d) {
    if (d == null) return false;
    final ini = DateTime(_inicio.year, _inicio.month, _inicio.day);
    final fim = DateTime(_fim.year, _fim.month, _fim.day, 23, 59, 59, 999);
    return !d.isBefore(ini) && !d.isAfter(fim);
  }

  DateTime? _cadastro(Map<String, dynamic> u) => _data(u['dt_cadastro']);

  DateTime? _acessoData(Map<String, dynamic> a) => _data(a['data_hora_acesso']);

  List<Map<String, dynamic>> get _usuariosPeriodo =>
      _usuarios.where((u) => _noPeriodo(_cadastro(u))).toList();

  List<Map<String, dynamic>> get _acessosPeriodo =>
      _acessos.where((a) => _noPeriodo(_acessoData(a))).toList();

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final r = await Future.wait<dynamic>([
        _supabase.from('tab_usuarios').select(
              'id, usuario_nome, cidade, estado, usuario_tipo, nome_plano_ativo, dt_cadastro, dt_nascimento, genero, recorrente, usuario_status, plano_data_ativacao, plano_expiracao',
            ),
        _supabase.from('tab_acessos').select(
              'id, usuario_id, sessao_id, data_hora_acesso, data_hora_saida, duracao_segundos, tipo_acesso, plataforma, dispositivo, sistema_operacional, versao_app, origem, pagina_inicial, ultima_pagina, sessao_ativa',
            ),
      ]);

      if (!mounted) return;
      setState(() {
        _usuarios = (r[0] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _acessos = (r[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _carregando = false;
      });
    } catch (e, st) {
      debugPrint('Erro métricas retenção: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

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
        if (_fim.isBefore(_inicio)) _inicio = _fim;
      });
    }
  }

  void _ultimosDias(int dias) {
    final agora = DateTime.now();
    setState(() {
      _fim = agora;
      _inicio = agora.subtract(Duration(days: dias - 1));
    });
  }

  void _todoPeriodo() {
    final datas = _usuarios.map(_cadastro).whereType<DateTime>().toList();
    if (datas.isEmpty) return;
    datas.sort();
    setState(() {
      _inicio = datas.first;
      _fim = DateTime.now();
    });
  }

  List<Map<String, dynamic>> _acessosUsuario(String id) {
    final lista = _acessos
        .where((a) => (a['usuario_id'] ?? '').toString() == id)
        .toList();
    lista.sort((a, b) {
      final da = _acessoData(a) ?? DateTime(1970);
      final db = _acessoData(b) ?? DateTime(1970);
      return da.compareTo(db);
    });
    return lista;
  }

  DateTime? _ultimoAcesso(String id) {
    final a = _acessosUsuario(id);
    return a.isEmpty ? null : _acessoData(a.last);
  }

  int _diasAtivos(String id) {
    final dias = <String>{};
    for (final a in _acessosUsuario(id)) {
      final d = _acessoData(a);
      if (d != null) dias.add('${d.year}-${d.month}-${d.day}');
    }
    return dias.length;
  }

  bool _retidoExato(Map<String, dynamic> u, int dia) {
    final cadastro = _cadastro(u);
    if (cadastro == null) return false;
    final alvo = DateTime(cadastro.year, cadastro.month, cadastro.day)
        .add(Duration(days: dia));
    final id = (u['id'] ?? '').toString();
    return _acessosUsuario(id).any((a) {
      final d = _acessoData(a);
      if (d == null) return false;
      return d.year == alvo.year && d.month == alvo.month && d.day == alvo.day;
    });
  }

  bool _elegivel(Map<String, dynamic> u, int dia) {
    final cadastro = _cadastro(u);
    if (cadastro == null) return false;
    final limite = DateTime.now().subtract(Duration(days: dia));
    return !cadastro.isAfter(limite);
  }

  Map<String, num> _marco(int dia) {
    final base = _usuariosPeriodo.where((u) => _elegivel(u, dia)).toList();
    final retidos = base.where((u) => _retidoExato(u, dia)).length;
    final pct = base.isEmpty ? 0.0 : (retidos / base.length) * 100;
    return {'elegiveis': base.length, 'retidos': retidos, 'percentual': pct};
  }

  int _ativosNosUltimos(int dias) {
    final limite = DateTime.now().subtract(Duration(days: dias));
    return _usuariosPeriodo.where((u) {
      final d = _ultimoAcesso((u['id'] ?? '').toString());
      return d != null && !d.isBefore(limite);
    }).length;
  }

  int _semAcesso() => _usuariosPeriodo.where((u) {
        final id = (u['id'] ?? '').toString();
        return _acessosUsuario(id).isEmpty;
      }).length;

  Map<String, Map<String, int>> _segmentar(String campo) {
    final out = <String, Map<String, int>>{};
    for (final u in _usuariosPeriodo) {
      final nome = (u[campo] ?? '').toString().trim().isEmpty
          ? 'Não informado'
          : u[campo].toString().trim();
      final id = (u['id'] ?? '').toString();
      final ultimo = _ultimoAcesso(id);
      out.putIfAbsent(
          nome, () => {'usuarios': 0, 'ativos30': 0, 'comAcesso': 0});
      out[nome]!['usuarios'] = out[nome]!['usuarios']! + 1;
      if (_acessosUsuario(id).isNotEmpty) {
        out[nome]!['comAcesso'] = out[nome]!['comAcesso']! + 1;
      }
      if (ultimo != null &&
          !ultimo.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
        out[nome]!['ativos30'] = out[nome]!['ativos30']! + 1;
      }
    }
    return out;
  }

  Map<String, Map<String, int>> _porRecorrencia() {
    final out = <String, Map<String, int>>{};
    for (final u in _usuariosPeriodo) {
      final nome = u['recorrente'] == true ? 'Recorrente' : 'Não recorrente';
      final id = (u['id'] ?? '').toString();
      final ultimo = _ultimoAcesso(id);
      out.putIfAbsent(
          nome, () => {'usuarios': 0, 'ativos30': 0, 'comAcesso': 0});
      out[nome]!['usuarios'] = out[nome]!['usuarios']! + 1;
      if (_acessosUsuario(id).isNotEmpty) {
        out[nome]!['comAcesso'] = out[nome]!['comAcesso']! + 1;
      }
      if (ultimo != null &&
          !ultimo.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
        out[nome]!['ativos30'] = out[nome]!['ativos30']! + 1;
      }
    }
    return out;
  }

  Map<String, Map<String, int>> _porFaixaEtaria() {
    final out = <String, Map<String, int>>{};
    for (final u in _usuariosPeriodo) {
      final n = _data(u['dt_nascimento']);
      String faixa = 'Não informado';
      if (n != null) {
        final agora = DateTime.now();
        var idade = agora.year - n.year;
        if (agora.month < n.month ||
            (agora.month == n.month && agora.day < n.day)) idade--;
        if (idade < 18)
          faixa = 'Menos de 18';
        else if (idade <= 24)
          faixa = '18-24';
        else if (idade <= 34)
          faixa = '25-34';
        else if (idade <= 44)
          faixa = '35-44';
        else if (idade <= 54)
          faixa = '45-54';
        else if (idade <= 64)
          faixa = '55-64';
        else
          faixa = '65+';
      }
      final id = (u['id'] ?? '').toString();
      final ultimo = _ultimoAcesso(id);
      out.putIfAbsent(
          faixa, () => {'usuarios': 0, 'ativos30': 0, 'comAcesso': 0});
      out[faixa]!['usuarios'] = out[faixa]!['usuarios']! + 1;
      if (_acessosUsuario(id).isNotEmpty)
        out[faixa]!['comAcesso'] = out[faixa]!['comAcesso']! + 1;
      if (ultimo != null &&
          !ultimo.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
        out[faixa]!['ativos30'] = out[faixa]!['ativos30']! + 1;
      }
    }
    return out;
  }

  Map<String, Map<String, int>> _coortes() {
    final out = <String, Map<String, int>>{};
    for (final u in _usuariosPeriodo) {
      final d = _cadastro(u);
      if (d == null) continue;
      final chave = '${d.month.toString().padLeft(2, '0')}/${d.year}';
      out.putIfAbsent(
          chave, () => {'cadastrados': 0, 'd1': 0, 'd7': 0, 'd30': 0});
      out[chave]!['cadastrados'] = out[chave]!['cadastrados']! + 1;
      if (_elegivel(u, 1) && _retidoExato(u, 1))
        out[chave]!['d1'] = out[chave]!['d1']! + 1;
      if (_elegivel(u, 7) && _retidoExato(u, 7))
        out[chave]!['d7'] = out[chave]!['d7']! + 1;
      if (_elegivel(u, 30) && _retidoExato(u, 30))
        out[chave]!['d30'] = out[chave]!['d30']! + 1;
    }
    return out;
  }

  Map<String, int> _evolucaoAcessos() {
    final out = <String, int>{};
    for (final a in _acessosPeriodo) {
      final d = _acessoData(a);
      if (d == null) continue;
      final chave =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      out[chave] = (out[chave] ?? 0) + 1;
    }
    return out;
  }

  List<Map<String, dynamic>> _ranking() {
    final lista = <Map<String, dynamic>>[];
    for (final u in _usuariosPeriodo) {
      final id = (u['id'] ?? '').toString();
      final acessos = _acessosUsuario(id);
      if (acessos.isEmpty) continue;
      lista.add({
        'nome': u['usuario_nome'] ?? 'Usuário',
        'plano': u['nome_plano_ativo'] ?? 'Não informado',
        'acessos': acessos.length,
        'dias': _diasAtivos(id),
        'ultimo': _ultimoAcesso(id),
      });
    }
    lista.sort((a, b) => (b['acessos'] as int).compareTo(a['acessos'] as int));
    return lista.take(20).toList();
  }

  Widget _periodo() {
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Período analisado',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _botaoData('Inicial', _inicio, _selecionarInicio),
              _botaoData('Final', _fim, _selecionarFim),
              _atalho('7 dias', () => _ultimosDias(7)),
              _atalho('30 dias', () => _ultimosDias(30)),
              _atalho('90 dias', () => _ultimosDias(90)),
              _atalho('1 ano', () => _ultimosDias(365)),
              _atalho('Todo o período', _todoPeriodo),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'O período seleciona as coortes pela data de cadastro. A atividade recente usa os acessos reais registrados em tab_acessos.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _botaoData(String titulo, DateTime data, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month, size: 18),
      label: Text('$titulo: ${_fmtData(data)}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _atalho(String texto, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: _laranja),
      child: Text(texto),
    );
  }

  Widget _cardBase({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _metrica(String titulo, String valor, IconData icone,
      {String? subtitulo}) {
    return Container(
      width: 210,
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: _laranja, size: 25),
          const SizedBox(height: 12),
          Text(valor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          if (subtitulo != null) ...[
            const SizedBox(height: 5),
            Text(subtitulo,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _titulo(String titulo, {String? subtitulo}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(subtitulo,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _semDados(String texto) {
    return _cardBase(
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: _laranja),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(texto, style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }

  Widget _marcosRetencao() {
    final dias = [1, 7, 30, 60, 90];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: dias.map((dia) {
        final m = _marco(dia);
        return _metrica(
          'Retenção D$dia',
          _fmtPct((m['percentual'] ?? 0).toDouble()),
          Icons.replay_circle_filled,
          subtitulo: '${m['retidos']} retidos de ${m['elegiveis']} elegíveis',
        );
      }).toList(),
    );
  }

  Widget _tabelaSegmento(String titulo, Map<String, Map<String, int>> dados) {
    final itens = dados.entries.toList()
      ..sort((a, b) =>
          (b.value['usuarios'] ?? 0).compareTo(a.value['usuarios'] ?? 0));
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (itens.isEmpty)
            const Text('Sem dados no período.',
                style: TextStyle(color: Colors.white54))
          else
            ...itens.take(20).map((e) {
              final total = e.value['usuarios'] ?? 0;
              final ativos = e.value['ativos30'] ?? 0;
              final pct = total == 0 ? 0.0 : ativos / total * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(e.key,
                            style: const TextStyle(color: Colors.white70))),
                    Text('$ativos / $total',
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(width: 14),
                    SizedBox(
                        width: 64,
                        child: Text(_fmtPct(pct),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: _laranja, fontWeight: FontWeight.bold))),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _coortesWidget() {
    final dados = _coortes();
    final itens = dados.entries.toList();
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Coortes por mês de cadastro',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('D1, D7 e D30 mostram retorno no dia exato do marco.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 14),
          if (itens.isEmpty)
            const Text('Sem coortes no período.',
                style: TextStyle(color: Colors.white54))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                    color: _laranja, fontWeight: FontWeight.bold),
                dataTextStyle: const TextStyle(color: Colors.white70),
                columns: const [
                  DataColumn(label: Text('Coorte')),
                  DataColumn(label: Text('Cadastros')),
                  DataColumn(label: Text('D1')),
                  DataColumn(label: Text('D7')),
                  DataColumn(label: Text('D30')),
                ],
                rows: itens.map((e) {
                  final t = e.value['cadastrados'] ?? 0;
                  String p(String k) {
                    final v = e.value[k] ?? 0;
                    return t == 0 ? '0%' : _fmtPct(v / t * 100);
                  }

                  return DataRow(cells: [
                    DataCell(Text(e.key)),
                    DataCell(Text('$t')),
                    DataCell(Text(p('d1'))),
                    DataCell(Text(p('d7'))),
                    DataCell(Text(p('d30'))),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _evolucaoWidget() {
    final dados = _evolucaoAcessos();
    final maxV = dados.values.fold<int>(0, (p, e) => e > p ? e : p);
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Evolução de acessos',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (dados.isEmpty)
            const Text('Ainda não há acessos registrados em tab_acessos.',
                style: TextStyle(color: Colors.white54))
          else
            ...dados.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 62,
                          child: Text(e.key,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: maxV == 0 ? 0 : e.value / maxV,
                            minHeight: 9,
                            backgroundColor: Colors.white10,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(_laranja),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 38,
                          child: Text('${e.value}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: Colors.white))),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _rankingWidget() {
    final dados = _ranking();
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Usuários mais engajados',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (dados.isEmpty)
            const Text('Sem acessos registrados para formar o ranking.',
                style: TextStyle(color: Colors.white54))
          else
            ...dados.asMap().entries.map((item) {
              final i = item.key + 1;
              final e = item.value;
              final ultimo = e['ultimo'] as DateTime?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                        width: 34,
                        child: Text('$iº',
                            style: const TextStyle(
                                color: _laranja, fontWeight: FontWeight.bold))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e['nome'].toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              '${e['plano']} • último: ${ultimo == null ? '—' : _fmtData(ultimo)}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('${e['acessos']} acessos',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 12),
                    Text('${e['dias']} dias',
                        style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _frequenciaWidget() {
    int um = 0, doisCinco = 0, seisDez = 0, onzeTrinta = 0, maisTrinta = 0;
    for (final u in _usuariosPeriodo) {
      final n = _acessosUsuario((u['id'] ?? '').toString()).length;
      if (n == 1)
        um++;
      else if (n >= 2 && n <= 5)
        doisCinco++;
      else if (n >= 6 && n <= 10)
        seisDez++;
      else if (n >= 11 && n <= 30)
        onzeTrinta++;
      else if (n > 30) maisTrinta++;
    }
    final dados = {
      '1 acesso': um,
      '2–5 acessos': doisCinco,
      '6–10 acessos': seisDez,
      '11–30 acessos': onzeTrinta,
      'Mais de 30': maisTrinta
    };
    return _cardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Frequência de uso',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ...dados.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(color: Colors.white70))),
                  Text('${e.value}',
                      style: const TextStyle(
                          color: _laranja, fontWeight: FontWeight.bold)),
                ]),
              )),
        ],
      ),
    );
  }

  Widget _conteudo() {
    final base = _usuariosPeriodo.length;
    final acessos = _acessosPeriodo.length;
    final ativos7 = _ativosNosUltimos(7);
    final ativos30 = _ativosNosUltimos(30);
    final ativos90 = _ativosNosUltimos(90);
    final semAcesso = _semAcesso();
    final usuariosComAcesso = base - semAcesso;
    final taxaComAcesso = base == 0 ? 0.0 : usuariosComAcesso / base * 100;

    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _laranja,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          _periodo(),
          _titulo('Visão geral',
              subtitulo: 'Permanência, retorno e atividade real dos usuários.'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metrica(
                  'Usuários da coorte', '$base', Icons.people_alt_outlined),
              _metrica('Com algum acesso', '$usuariosComAcesso', Icons.login,
                  subtitulo: _fmtPct(taxaComAcesso)),
              _metrica('Ativos em 7 dias', '$ativos7', Icons.bolt),
              _metrica(
                  'Ativos em 30 dias', '$ativos30', Icons.calendar_view_month),
              _metrica('Ativos em 90 dias', '$ativos90', Icons.history),
              _metrica('Sem acesso registrado', '$semAcesso',
                  Icons.person_off_outlined),
              _metrica(
                  'Acessos no período', '$acessos', Icons.touch_app_outlined),
            ],
          ),
          if (_acessos.isEmpty) ...[
            const SizedBox(height: 18),
            _semDados(
                'A tabela tab_acessos ainda está sem registros. A tela já está pronta; D1/D7/D30/D60/D90, sessões, frequência e rankings começarão a refletir uso real assim que o app registrar acessos.'),
          ],
          _titulo('Retenção por marco',
              subtitulo:
                  'Somente usuários maduros entram no denominador de cada marco.'),
          _marcosRetencao(),
          _titulo('Coortes e evolução'),
          _coortesWidget(),
          const SizedBox(height: 12),
          _evolucaoWidget(),
          _titulo('Frequência e engajamento'),
          _frequenciaWidget(),
          const SizedBox(height: 12),
          _rankingWidget(),
          _titulo('Retenção por plano'),
          _tabelaSegmento('Plano atual • ativos nos últimos 30 dias',
              _segmentar('nome_plano_ativo')),
          _titulo('Retenção por público'),
          _tabelaSegmento('Tipo de usuário', _segmentar('usuario_tipo')),
          const SizedBox(height: 12),
          _tabelaSegmento('Recorrência', _porRecorrencia()),
          const SizedBox(height: 12),
          _tabelaSegmento('Gênero', _segmentar('genero')),
          const SizedBox(height: 12),
          _tabelaSegmento('Faixa etária', _porFaixaEtaria()),
          _titulo('Retenção geográfica'),
          _tabelaSegmento('Estados', _segmentar('estado')),
          const SizedBox(height: 12),
          _tabelaSegmento('Cidades', _segmentar('cidade')),
          _titulo('Critérios da métrica'),
          _cardBase(
            child: const Text(
              '• D1, D7, D30, D60 e D90: retorno no dia exato após o cadastro.\n'
              '• Coortes: usuários cadastrados dentro do período selecionado.\n'
              '• Ativos 7/30/90 dias: último acesso real em tab_acessos.\n'
              '• Usuário com status "ativo" não é considerado ativo de uso sem registro de acesso.\n'
              '• Usuários recém-cadastrados não entram em marcos que ainda não tiveram tempo de atingir.',
              style: TextStyle(color: Colors.white60, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundoEscuro,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Retenção', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Permanência e recorrência',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarDados,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 44),
                        const SizedBox(height: 12),
                        const Text(
                            'Não foi possível carregar as métricas de retenção.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_erro!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _carregarDados,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _laranja,
                              foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              : _conteudo(),
    );
  }
}
