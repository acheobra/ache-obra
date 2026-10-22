import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasCrescimentoPage extends StatefulWidget {
  final int metaInicial;

  const MetricasCrescimentoPage({
    super.key,
    this.metaInicial = 10000,
  });

  @override
  State<MetricasCrescimentoPage> createState() =>
      _MetricasCrescimentoPageState();
}

class _MetricasCrescimentoPageState extends State<MetricasCrescimentoPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _card = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);

  bool _carregando = true;
  String? _erro;
  List<DateTime> _cadastros = [];
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  late int _metaUsuarios;

  @override
  void initState() {
    super.initState();
    _metaUsuarios = widget.metaInicial;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    _dataFinal = hoje;
    _dataInicial = hoje.subtract(const Duration(days: 29));
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('tab_usuarios')
          .select('dt_cadastro');

      final datas = <DateTime>[];
      for (final item in response as List) {
        final valor = (item as Map)['dt_cadastro'];
        if (valor == null) continue;
        final d = DateTime.tryParse(valor.toString());
        if (d != null) datas.add(DateTime(d.year, d.month, d.day));
      }

      if (!mounted) return;
      setState(() {
        _cadastros = datas;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro em métricas de crescimento: $e');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  int get _totalPeriodo {
    final inicio = _dataInicial;
    final fim = _dataFinal;
    return _cadastros.where((d) {
      if (inicio != null && d.isBefore(inicio)) return false;
      if (fim != null && d.isAfter(fim)) return false;
      return true;
    }).length;
  }

  int get _totalBase => _cadastros.length;

  double get _progresso {
    if (_metaUsuarios <= 0) return 0;
    return (_totalBase / _metaUsuarios).clamp(0.0, 1.0);
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'Selecionar';
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  String _numero(int valor) {
    final texto = valor.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < texto.length; i++) {
      final restante = texto.length - i;
      buffer.write(texto[i]);
      if (restante > 1 && restante % 3 == 1) buffer.write('.');
    }
    return buffer.toString();
  }

  Future<void> _selecionarData(bool inicial) async {
    final agora = DateTime.now();
    final atual = inicial ? _dataInicial : _dataFinal;

    final escolhida = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: atual ?? agora,
      primeiraData: DateTime(2020, 1, 1),
      ultimaData: DateTime(agora.year + 5, 12, 31),
      titulo: inicial ? 'Selecionar data inicial' : 'Selecionar data final',
    );

    if (escolhida == null || !mounted) return;

    setState(() {
      if (inicial) {
        _dataInicial = escolhida;
        if (_dataFinal != null && _dataFinal!.isBefore(escolhida)) {
          _dataFinal = escolhida;
        }
      } else {
        _dataFinal = escolhida;
        if (_dataInicial != null && _dataInicial!.isAfter(escolhida)) {
          _dataInicial = escolhida;
        }
      }
    });
  }

  void _periodoRapido(int dias) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    setState(() {
      _dataFinal = hoje;
      _dataInicial = hoje.subtract(Duration(days: dias - 1));
    });
  }

  Future<void> _editarMeta() async {
    final controller = TextEditingController(text: _metaUsuarios.toString());
    final novaMeta = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Alterar meta',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Meta de usuários',
            labelStyle: TextStyle(color: Colors.white60),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = int.tryParse(
                controller.text.replaceAll('.', '').replaceAll(',', ''),
              );
              if (valor != null && valor > 0) {
                Navigator.pop(dialogContext, valor);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _laranja),
            child: const Text(
              'APLICAR',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
    controller.dispose();

    if (novaMeta != null && mounted) {
      setState(() => _metaUsuarios = novaMeta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentual = _progresso * 100;

    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Crescimento'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filtros(),
            const SizedBox(height: 22),
            if (_erro != null) ...[
              Text(
                'Erro ao carregar dados: $_erro',
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 22),
            ],
            _painel(
              titulo: 'Crescimento no Período',
              child: Row(
                children: [
                  const Icon(Icons.trending_up, color: _laranja, size: 34),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _carregando ? '...' : '+${_numero(_totalPeriodo)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_formatarData(_dataInicial)} até ${_formatarData(_dataFinal)}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _painel(
              titulo: 'Meta de Usuários',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_numero(_totalBase)} / ${_numero(_metaUsuarios)} usuários',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Alterar meta',
                        onPressed: _editarMeta,
                        icon: const Icon(Icons.edit_outlined, color: _laranja),
                      ),
                      Text(
                        '${percentual.toStringAsFixed(2).replaceAll('.', ',')}%',
                        style: const TextStyle(
                          color: _laranja,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: _progresso,
                      minHeight: 15,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _totalBase >= _metaUsuarios
                        ? 'Meta atingida.'
                        : 'Faltam ${_numero(_metaUsuarios - _totalBase)} usuários para atingir a meta.',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return _painel(
      titulo: 'Período',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _dataButton('Inicial', _dataInicial, () => _selecionarData(true)),
          _dataButton('Final', _dataFinal, () => _selecionarData(false)),
          OutlinedButton(
            onPressed: () => _periodoRapido(7),
            child: const Text('7 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(30),
            child: const Text('30 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(90),
            child: const Text('90 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(365),
            child: const Text('1 ano'),
          ),
        ],
      ),
    );
  }

  Widget _dataButton(String label, DateTime? data, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label: ${_formatarData(data)}'),
      style: OutlinedButton.styleFrom(foregroundColor: _laranja),
    );
  }

  Widget _painel({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _laranja,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
