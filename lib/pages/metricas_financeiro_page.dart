import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasFinanceiroPage extends StatefulWidget {
  const MetricasFinanceiroPage({super.key});

  @override
  State<MetricasFinanceiroPage> createState() => _MetricasFinanceiroPageState();
}

class _MetricasFinanceiroPageState extends State<MetricasFinanceiroPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _card = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);
  static const Color _verde = Color(0xFF2ECC71);
  static const Color _vermelho = Color(0xFFE74C3C);
  static const Color _azul = Color(0xFF3498DB);

  final SupabaseClient _supabase = Supabase.instance.client;

  bool _carregando = true;
  String? _erro;

  DateTime? _dataInicial;
  DateTime? _dataFinal;

  List<Map<String, dynamic>> _pagamentosRecorrentes = [];
  List<Map<String, dynamic>> _pagamentosAvulsos = [];
  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _assinaturasGoogle = [];
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _definirPeriodoInicial();
    _carregar();
  }

  void _definirPeriodoInicial() {
    final agora = DateTime.now();
    _dataFinal = DateTime(agora.year, agora.month, agora.day);
    _dataInicial = _dataFinal!.subtract(const Duration(days: 29));
  }

  DateTime get _inicioEfetivo =>
      _dataInicial ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime get _fimEfetivo {
    final d = _dataFinal ?? DateTime.now();
    return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  }

  Future<List<Map<String, dynamic>>> _buscarTodos(
    String tabela,
    String campos,
  ) async {
    const tamanhoPagina = 1000;
    var inicio = 0;
    final resultado = <Map<String, dynamic>>[];

    while (true) {
      final resposta = await _supabase.from(tabela).select(campos).range(
            inicio,
            inicio + tamanhoPagina - 1,
          );

      final pagina = List<Map<String, dynamic>>.from(resposta);
      resultado.addAll(pagina);

      if (pagina.length < tamanhoPagina) break;
      inicio += tamanhoPagina;
    }

    return resultado;
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resultados = await Future.wait([
        _buscarTodos(
          'tab_pagamentos_recorrentes',
          'id,assinatura_id,usuario_id,plano_id,efi_subscription_id,'
              'efi_plan_id,efi_charge_id,valor,parcelas,valor_parcela,status,'
              'status_efi,metodo_pagamento,bandeira_cartao,data_cobranca,'
              'data_vencimento,data_pagamento,data_recusa,data_cancelamento,'
              'data_estorno,codigo_recusa,motivo_recusa,motivo_cancelamento,'
              'valor_estornado,origem_registro,created_at,updated_at',
        ),
        _buscarTodos(
          'tab_pagamentos_avulsos',
          'id,usuario_id,origem_tipo,origem_id,tipo_pagamento,valor,'
              'efi_charge_id,pix_txid,pix_e2e_id,status,data_pagamento,'
              'estorno_solicitado_em,estorno_concluido_em,motivo_cancelamento,'
              'created_at',
        ),
        _buscarTodos(
          'tab_assinaturas',
          'id,usuario_id,plano_id,efi_subscription_id,efi_plan_id,'
              'efi_charge_id,status_assinatura,ultimo_status_efi,'
              'valor_recorrente,data_inicio,data_ultimo_pagamento,'
              'proxima_cobranca_em,data_inicio_inadimplencia,data_fim_carencia,'
              'cancelado_em,motivo_cancelamento,created_at,updated_at',
        ),
        _buscarTodos(
          'tab_assinaturas_google',
          'id,usuario_id,plano_id,google_product_id,google_base_plan_id,'
              'google_order_id,status_assinatura,acknowledgement_state,'
              'auto_renovacao,data_inicio,data_expiracao,data_ultimo_pagamento,'
              'cancelado_em,created_at,updated_at,tipo_compra,recorrente',
        ),
        _buscarTodos(
          'tab_pedidos',
          'id,usuario_id,origem_tipo,origem_id,valor,status,metodo_pagamento,'
              'created_at,updated_at,efi_txid,efi_charge_id',
        ),
        _buscarTodos(
          'tab_planos',
          'id,nome_plano,valor,valor_recorrente,status,tipo_usuario,'
              'recorrencia_ativa,google_product_id,google_base_plan_id,'
              'google_ativo,google_product_id_avulso',
        ),
        _buscarTodos(
          'tab_usuarios',
          'id,usuario_nome,cidade,estado,usuario_tipo,plano_id,'
              'id_plano_atual,nome_plano_ativo,recorrente,usuario_status',
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _pagamentosRecorrentes = resultados[0];
        _pagamentosAvulsos = resultados[1];
        _assinaturas = resultados[2];
        _assinaturasGoogle = resultados[3];
        _pedidos = resultados[4];
        _planos = resultados[5];
        _usuarios = resultados[6];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as métricas financeiras.\n$e';
      });
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  String _normalizar(dynamic valor) =>
      (valor ?? '').toString().trim().toLowerCase();

  double _numeroValor(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor.toString().replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        double.tryParse(valor.toString()) ??
        0;
  }

  DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor.toLocal();
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  bool _noPeriodo(DateTime? data) {
    if (data == null) return false;
    return !data.isBefore(_inicioEfetivo) && !data.isAfter(_fimEfetivo);
  }

  bool _contemAlgum(String valor, List<String> termos) =>
      termos.any(valor.contains);

  bool _statusPago(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'pago',
      'paid',
      'approved',
      'aprovado',
      'completed',
      'concluido',
      'concluído',
      'confirmado',
      'settled',
    ]);
  }

  bool _statusPendente(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'pendente',
      'pending',
      'waiting',
      'aguardando',
      'processing',
      'processando',
    ]);
  }

  bool _statusRecusado(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'recus',
      'refus',
      'denied',
      'declined',
      'failed',
      'falha',
      'error',
      'erro',
    ]);
  }

  bool _statusCancelado(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'cancel',
      'canceled',
      'cancelled',
      'inactive',
      'inativo',
    ]);
  }

  bool _statusAtivo(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'ativo',
      'active',
      'paid',
      'pago',
      'approved',
      'aprovado',
    ]);
  }

  bool _statusEstornado(dynamic status) {
    final s = _normalizar(status);
    return _contemAlgum(s, [
      'estorn',
      'refund',
      'refunded',
      'chargeback',
    ]);
  }

  DateTime? _dataFinanceiraRecorrente(Map<String, dynamic> r) {
    if (_statusPago(r['status']) || _statusPago(r['status_efi'])) {
      return _data(r['data_pagamento']) ??
          _data(r['data_cobranca']) ??
          _data(r['created_at']);
    }
    if (_statusRecusado(r['status']) || _statusRecusado(r['status_efi'])) {
      return _data(r['data_recusa']) ??
          _data(r['data_cobranca']) ??
          _data(r['created_at']);
    }
    if (_statusCancelado(r['status']) || _statusCancelado(r['status_efi'])) {
      return _data(r['data_cancelamento']) ??
          _data(r['data_cobranca']) ??
          _data(r['created_at']);
    }
    if (_statusEstornado(r['status']) || _statusEstornado(r['status_efi'])) {
      return _data(r['data_estorno']) ??
          _data(r['data_pagamento']) ??
          _data(r['created_at']);
    }
    return _data(r['data_cobranca']) ?? _data(r['created_at']);
  }

  DateTime? _dataFinanceiraAvulso(Map<String, dynamic> r) {
    if (_statusPago(r['status'])) {
      return _data(r['data_pagamento']) ?? _data(r['created_at']);
    }
    if (_statusEstornado(r['status'])) {
      return _data(r['estorno_concluido_em']) ??
          _data(r['data_pagamento']) ??
          _data(r['created_at']);
    }
    return _data(r['created_at']);
  }

  List<Map<String, dynamic>> get _recorrentesPeriodo => _pagamentosRecorrentes
      .where((r) => _noPeriodo(_dataFinanceiraRecorrente(r)))
      .toList();

  List<Map<String, dynamic>> get _avulsosPeriodo => _pagamentosAvulsos
      .where((r) => _noPeriodo(_dataFinanceiraAvulso(r)))
      .toList();

  List<Map<String, dynamic>> get _recorrentesPagosPeriodo =>
      _pagamentosRecorrentes.where((r) {
        final pago = _statusPago(r['status']) || _statusPago(r['status_efi']);
        final dataPagamento =
            _data(r['data_pagamento']) ?? _data(r['data_cobranca']);
        return pago && _noPeriodo(dataPagamento);
      }).toList();

  List<Map<String, dynamic>> get _avulsosPagosPeriodo =>
      _pagamentosAvulsos.where((r) {
        return _statusPago(r['status']) &&
            _noPeriodo(_data(r['data_pagamento']) ?? _data(r['created_at']));
      }).toList();

  double get _receitaRecorrenteBruta => _recorrentesPagosPeriodo.fold(
        0.0,
        (soma, r) => soma + _numeroValor(r['valor']),
      );

  double get _receitaAvulsaBruta => _avulsosPagosPeriodo.fold(
        0.0,
        (soma, r) => soma + _numeroValor(r['valor']),
      );

  double get _estornosRecorrentes {
    return _pagamentosRecorrentes.where((r) {
      final dataEstorno = _data(r['data_estorno']);
      final temEstorno = _numeroValor(r['valor_estornado']) > 0 ||
          _statusEstornado(r['status']) ||
          _statusEstornado(r['status_efi']);
      return temEstorno && _noPeriodo(dataEstorno);
    }).fold(0.0, (soma, r) {
      final valorEstornado = _numeroValor(r['valor_estornado']);
      return soma +
          (valorEstornado > 0 ? valorEstornado : _numeroValor(r['valor']));
    });
  }

  double get _estornosAvulsos {
    return _pagamentosAvulsos.where((r) {
      return _noPeriodo(_data(r['estorno_concluido_em']));
    }).fold(0.0, (soma, r) => soma + _numeroValor(r['valor']));
  }

  double get _receitaBruta => _receitaRecorrenteBruta + _receitaAvulsaBruta;

  double get _estornos => _estornosRecorrentes + _estornosAvulsos;

  double get _receitaLiquidaRegistrada =>
      math.max(0.0, _receitaBruta - _estornos);

  int get _quantidadePagamentos =>
      _recorrentesPagosPeriodo.length + _avulsosPagosPeriodo.length;

  double get _ticketMedio =>
      _quantidadePagamentos == 0 ? 0 : _receitaBruta / _quantidadePagamentos;

  Set<String> get _usuariosPagantes {
    final ids = <String>{};
    for (final r in _recorrentesPagosPeriodo) {
      final id = r['usuario_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    for (final r in _avulsosPagosPeriodo) {
      final id = r['usuario_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  int get _cobrancasRecorrentes => _recorrentesPeriodo.length;

  int get _cobrancasPagas => _recorrentesPeriodo.where((r) {
        return _statusPago(r['status']) || _statusPago(r['status_efi']);
      }).length;

  int get _cobrancasPendentes => _recorrentesPeriodo.where((r) {
        return _statusPendente(r['status']) || _statusPendente(r['status_efi']);
      }).length;

  int get _cobrancasRecusadas => _recorrentesPeriodo.where((r) {
        return _statusRecusado(r['status']) || _statusRecusado(r['status_efi']);
      }).length;

  int get _cobrancasCanceladas => _recorrentesPeriodo.where((r) {
        return _statusCancelado(r['status']) ||
            _statusCancelado(r['status_efi']);
      }).length;

  int get _cobrancasEstornadas => _pagamentosRecorrentes.where((r) {
        final temEstorno = _numeroValor(r['valor_estornado']) > 0 ||
            _statusEstornado(r['status']) ||
            _statusEstornado(r['status_efi']);
        return temEstorno && _noPeriodo(_data(r['data_estorno']));
      }).length;

  double _percentual(num parte, num total) =>
      total == 0 ? 0 : (parte / total) * 100;

  List<Map<String, dynamic>> get _assinaturasAtivas {
    return _assinaturas.where((a) {
      final statusAtivo = _statusAtivo(a['status_assinatura']);
      final cancelada = a['cancelado_em'] != null;
      return statusAtivo && !cancelada;
    }).toList();
  }

  List<Map<String, dynamic>> get _assinaturasGoogleAtivas {
    return _assinaturasGoogle.where((a) {
      final statusAtivo = _statusAtivo(a['status_assinatura']);
      final cancelada = a['cancelado_em'] != null;
      final recorrente = a['recorrente'] == true || a['auto_renovacao'] == true;
      return statusAtivo && !cancelada && recorrente;
    }).toList();
  }

  int get _assinaturasAtivasTotal =>
      _assinaturasAtivas.length + _assinaturasGoogleAtivas.length;

  int get _assinaturasInadimplentes => _assinaturas.where((a) {
        final inicio = _data(a['data_inicio_inadimplencia']);
        final cancelada = a['cancelado_em'] != null;
        return inicio != null && !cancelada;
      }).length;

  double get _mrrEstimado {
    double total = 0;
    for (final a in _assinaturasAtivas) {
      total += _numeroValor(a['valor_recorrente']);
    }

    final planoPorId = <String, Map<String, dynamic>>{
      for (final p in _planos)
        if (p['id'] != null) p['id'].toString(): p,
    };

    for (final a in _assinaturasGoogleAtivas) {
      final p = planoPorId[a['plano_id']?.toString()];
      if (p != null) {
        final recorrente = _numeroValor(p['valor_recorrente']);
        total += recorrente > 0 ? recorrente : _numeroValor(p['valor']);
      }
    }
    return total;
  }

  double get _receitaPrevistaProximos30Dias {
    final agora = DateTime.now();
    final limite = agora.add(const Duration(days: 30));
    return _assinaturas.where((a) {
      final d = _data(a['proxima_cobranca_em']);
      if (d == null || a['cancelado_em'] != null) return false;
      return !d.isBefore(agora) && !d.isAfter(limite);
    }).fold(
      0.0,
      (soma, a) => soma + _numeroValor(a['valor_recorrente']),
    );
  }

  int get _cancelamentosPeriodo {
    final efi =
        _assinaturas.where((a) => _noPeriodo(_data(a['cancelado_em']))).length;
    final google = _assinaturasGoogle
        .where((a) => _noPeriodo(_data(a['cancelado_em'])))
        .length;
    return efi + google;
  }

  Map<String, double> get _receitaPorPlano {
    final resultado = <String, double>{};
    final nomePorId = <String, String>{
      for (final p in _planos)
        if (p['id'] != null)
          p['id'].toString(): (p['nome_plano'] ?? 'Plano sem nome').toString(),
    };

    for (final r in _recorrentesPagosPeriodo) {
      final id = r['plano_id']?.toString();
      final nome = id == null
          ? 'Sem plano identificado'
          : nomePorId[id] ?? 'Plano não localizado';
      resultado[nome] = (resultado[nome] ?? 0) + _numeroValor(r['valor']);
    }

    return resultado;
  }

  Map<String, int> get _pagamentosPorMetodo {
    final resultado = <String, int>{};

    void adicionar(dynamic valor) {
      final nome = (valor ?? 'Não informado').toString().trim();
      final chave = nome.isEmpty ? 'Não informado' : nome;
      resultado[chave] = (resultado[chave] ?? 0) + 1;
    }

    for (final r in _recorrentesPagosPeriodo) {
      adicionar(r['metodo_pagamento']);
    }
    for (final r in _avulsosPagosPeriodo) {
      adicionar(r['tipo_pagamento']);
    }
    return resultado;
  }

  Map<String, int> get _pagamentosPorBandeira {
    final resultado = <String, int>{};
    for (final r in _recorrentesPagosPeriodo) {
      final valor = (r['bandeira_cartao'] ?? '').toString().trim();
      if (valor.isEmpty) continue;
      resultado[valor] = (resultado[valor] ?? 0) + 1;
    }
    return resultado;
  }

  Map<String, int> get _recusasPorMotivo {
    final resultado = <String, int>{};
    for (final r in _recorrentesPeriodo) {
      if (!(_statusRecusado(r['status']) || _statusRecusado(r['status_efi']))) {
        continue;
      }
      final motivo =
          (r['motivo_recusa'] ?? r['codigo_recusa'] ?? 'Motivo não informado')
              .toString()
              .trim();
      final chave = motivo.isEmpty ? 'Motivo não informado' : motivo;
      resultado[chave] = (resultado[chave] ?? 0) + 1;
    }
    return resultado;
  }

  Map<String, double> get _receitaPorTipoUsuario {
    final usuarioPorId = <String, Map<String, dynamic>>{
      for (final u in _usuarios)
        if (u['id'] != null) u['id'].toString(): u,
    };
    final resultado = <String, double>{};

    void adicionar(Map<String, dynamic> r) {
      final u = usuarioPorId[r['usuario_id']?.toString()];
      final tipo = (u?['usuario_tipo'] ?? 'Não informado').toString().trim();
      final chave = tipo.isEmpty ? 'Não informado' : tipo;
      resultado[chave] = (resultado[chave] ?? 0) + _numeroValor(r['valor']);
    }

    for (final r in _recorrentesPagosPeriodo) {
      adicionar(r);
    }
    for (final r in _avulsosPagosPeriodo) {
      adicionar(r);
    }
    return resultado;
  }

  Map<String, double> get _receitaPorEstado {
    final usuarioPorId = <String, Map<String, dynamic>>{
      for (final u in _usuarios)
        if (u['id'] != null) u['id'].toString(): u,
    };
    final resultado = <String, double>{};

    void adicionar(Map<String, dynamic> r) {
      final u = usuarioPorId[r['usuario_id']?.toString()];
      final estado = (u?['estado'] ?? 'Não informado').toString().trim();
      final chave = estado.isEmpty ? 'Não informado' : estado;
      resultado[chave] = (resultado[chave] ?? 0) + _numeroValor(r['valor']);
    }

    for (final r in _recorrentesPagosPeriodo) {
      adicionar(r);
    }
    for (final r in _avulsosPagosPeriodo) {
      adicionar(r);
    }
    return resultado;
  }

  Map<DateTime, double> get _receitaDiaria {
    final resultado = <DateTime, double>{};

    void adicionar(DateTime? d, double valor) {
      if (d == null || !_noPeriodo(d)) return;
      final chave = DateTime(d.year, d.month, d.day);
      resultado[chave] = (resultado[chave] ?? 0) + valor;
    }

    for (final r in _recorrentesPagosPeriodo) {
      adicionar(
        _data(r['data_pagamento']) ?? _data(r['data_cobranca']),
        _numeroValor(r['valor']),
      );
    }
    for (final r in _avulsosPagosPeriodo) {
      adicionar(
        _data(r['data_pagamento']) ?? _data(r['created_at']),
        _numeroValor(r['valor']),
      );
    }
    return resultado;
  }

  double get _receitaPedidosPeriodo {
    return _pedidos.where((p) {
      return _statusPago(p['status']) && _noPeriodo(_data(p['created_at']));
    }).fold(0.0, (soma, p) => soma + _numeroValor(p['valor']));
  }

  Future<void> _selecionarData(bool inicial) async {
    final atual = inicial ? _dataInicial : _dataFinal;
    final escolhida = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: atual ?? DateTime.now(),
      titulo: inicial ? 'Data inicial' : 'Data final',
    );

    if (escolhida == null || !mounted) return;

    setState(() {
      if (inicial) {
        _dataInicial = escolhida;
        if (_dataFinal != null && escolhida.isAfter(_dataFinal!)) {
          _dataFinal = escolhida;
        }
      } else {
        _dataFinal = escolhida;
        if (_dataInicial != null && escolhida.isBefore(_dataInicial!)) {
          _dataInicial = escolhida;
        }
      }
    });
  }

  void _periodo(int dias) {
    final agora = DateTime.now();
    setState(() {
      _dataFinal = DateTime(agora.year, agora.month, agora.day);
      _dataInicial = _dataFinal!.subtract(Duration(days: dias - 1));
    });
  }

  void _todoPeriodo() {
    DateTime? menor;

    void considerar(dynamic valor) {
      final d = _data(valor);
      if (d != null && (menor == null || d.isBefore(menor!))) menor = d;
    }

    for (final r in _pagamentosRecorrentes) {
      considerar(r['data_pagamento']);
      considerar(r['data_cobranca']);
      considerar(r['created_at']);
    }
    for (final r in _pagamentosAvulsos) {
      considerar(r['data_pagamento']);
      considerar(r['created_at']);
    }

    final agora = DateTime.now();
    setState(() {
      final inicio = menor ?? DateTime(agora.year, 1, 1);
      _dataInicial = DateTime(inicio.year, inicio.month, inicio.day);
      _dataFinal = DateTime(agora.year, agora.month, agora.day);
    });
  }

  String _dataTexto(DateTime? d) {
    if (d == null) return '--/--/----';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _moeda(double valor) {
    final negativo = valor < 0;
    final absoluto = valor.abs();
    final inteiro = absoluto.floor();
    final centavos = ((absoluto - inteiro) * 100).round();
    final partes = inteiro.toString().split('');
    final buffer = StringBuffer();

    for (var i = 0; i < partes.length; i++) {
      final faltam = partes.length - i;
      buffer.write(partes[i]);
      if (faltam > 1 && (faltam - 1) % 3 == 0) buffer.write('.');
    }

    return '${negativo ? '-' : ''}R\$ ${buffer.toString()},'
        '${centavos.toString().padLeft(2, '0')}';
  }

  String _inteiro(num valor) {
    final s = valor.round().toString();
    final chars = s.split('');
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final faltam = chars.length - i;
      buffer.write(chars[i]);
      if (faltam > 1 && (faltam - 1) % 3 == 0) buffer.write('.');
    }
    return buffer.toString();
  }

  String _pct(double valor) =>
      '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';

  List<MapEntry<String, T>> _ordenarMapa<T extends num>(Map<String, T> mapa) {
    final lista = mapa.entries.toList();
    lista.sort((a, b) => b.value.compareTo(a.value));
    return lista;
  }

  Widget _botaoData(String titulo, DateTime? data, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text('$titulo: ${_dataTexto(data)}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _painel(String titulo, String subtitulo, Widget filho) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _laranja,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitulo,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 18),
          filho,
        ],
      ),
    );
  }

  Widget _grade(List<Widget> itens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        int colunas = 4;
        if (largura < 1150) colunas = 3;
        if (largura < 820) colunas = 2;
        if (largura < 520) colunas = 1;

        final espacos = (colunas - 1) * 12;
        final larguraItem = (largura - espacos) / colunas;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              itens.map((w) => SizedBox(width: larguraItem, child: w)).toList(),
        );
      },
    );
  }

  Widget _indicador(
    String titulo,
    String valor,
    IconData icone, {
    String? detalhe,
    Color? cor,
  }) {
    final destaque = cor ?? _laranja;
    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: destaque, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            valor,
            style: TextStyle(
              color: destaque,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (detalhe != null) ...[
            const SizedBox(height: 5),
            Text(
              detalhe,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rankingNumero(
    Map<String, int> dados, {
    int limite = 10,
    String sufixo = '',
  }) {
    final lista = _ordenarMapa(dados).take(limite).toList();
    if (lista.isEmpty) return _vazio('Nenhum dado disponível no período.');

    final maior = lista.first.value.toDouble();

    return Column(
      children: lista.map((e) {
        final proporcao = maior == 0 ? 0.0 : e.value / maior;
        return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_inteiro(e.value)}$sufixo',
                    style: const TextStyle(
                      color: _laranja,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: proporcao,
                  minHeight: 7,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _rankingMoeda(
    Map<String, double> dados, {
    int limite = 10,
  }) {
    final lista = _ordenarMapa(dados).take(limite).toList();
    if (lista.isEmpty) return _vazio('Nenhuma receita disponível no período.');

    final maior = lista.first.value.toDouble();

    return Column(
      children: lista.map((e) {
        final proporcao = maior == 0 ? 0.0 : e.value / maior;
        final participacao = _percentual(e.value, _receitaBruta);
        return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_moeda(e.value)} • ${_pct(participacao)}',
                    style: const TextStyle(
                      color: _laranja,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: proporcao,
                  minHeight: 7,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _evolucaoReceita() {
    final mapa = _receitaDiaria;
    if (mapa.isEmpty) return _vazio('Nenhuma receita paga no período.');

    final datas = mapa.keys.toList()..sort();
    final maior = mapa.values.fold<double>(0, math.max);

    return SizedBox(
      height: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: datas.map((d) {
          final valor = mapa[d] ?? 0;
          final altura = maior <= 0 ? 0.0 : (valor / maior) * 165;
          return Expanded(
            child: Tooltip(
              message: '${_dataTexto(d)} • ${_moeda(valor)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      valor > 0 ? _moeda(valor) : '',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: math.max(3, altura),
                      decoration: BoxDecoration(
                        color: _laranja,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${d.day}/${d.month}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _vazio(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  Widget _erroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _vermelho.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _vermelho.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _vermelho),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _erro ?? '',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: _carregar,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _observacaoDados() {
    final diferencaPedidos = (_receitaPedidosPeriodo - _receitaBruta).abs();
    final haDiferenca = diferencaPedidos > 0.01;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _azul.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _azul.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _azul),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'A receita principal desta tela é calculada pelos registros de '
              'pagamentos recorrentes e avulsos efetivamente pagos. '
              'tab_pedidos é usada apenas como conferência para evitar '
              'contabilizar a mesma venda duas vezes.'
              '${haDiferenca ? ' No período, pedidos marcados como pagos somam ${_moeda(_receitaPedidosPeriodo)}, valor que pode representar outra etapa do fluxo de cobrança.' : ''}',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taxaAprovacao = _percentual(_cobrancasPagas, _cobrancasRecorrentes);
    final taxaRecusa = _percentual(_cobrancasRecusadas, _cobrancasRecorrentes);
    final taxaEstorno = _percentual(_estornos, _receitaBruta);

    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas Financeiras'),
        actions: [
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: _laranja),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _painel(
                      'Período financeiro',
                      'Todos os indicadores de movimentação são recalculados pelo período selecionado. Assinaturas ativas e MRR mostram a posição atual da base.',
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _botaoData(
                            'Data inicial',
                            _dataInicial,
                            () => _selecionarData(true),
                          ),
                          _botaoData(
                            'Data final',
                            _dataFinal,
                            () => _selecionarData(false),
                          ),
                          OutlinedButton(
                            onPressed: () => _periodo(7),
                            child: const Text('7 dias'),
                          ),
                          OutlinedButton(
                            onPressed: () => _periodo(30),
                            child: const Text('30 dias'),
                          ),
                          OutlinedButton(
                            onPressed: () => _periodo(90),
                            child: const Text('90 dias'),
                          ),
                          OutlinedButton(
                            onPressed: () => _periodo(365),
                            child: const Text('1 ano'),
                          ),
                          TextButton(
                            onPressed: _todoPeriodo,
                            child: const Text('Todo o período'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_erro != null) ...[
                      _erroCard(),
                      const SizedBox(height: 20),
                    ],
                    _painel(
                      'Resumo financeiro',
                      'Receita realizada a partir dos registros de pagamentos.',
                      _grade([
                        _indicador(
                          'RECEITA BRUTA',
                          _moeda(_receitaBruta),
                          Icons.payments_outlined,
                          detalhe: 'recorrente + avulsa',
                          cor: _verde,
                        ),
                        _indicador(
                          'RECEITA LÍQUIDA REGISTRADA',
                          _moeda(_receitaLiquidaRegistrada),
                          Icons.account_balance_wallet_outlined,
                          detalhe: 'bruta menos estornos registrados',
                          cor: _verde,
                        ),
                        _indicador(
                          'RECEITA RECORRENTE',
                          _moeda(_receitaRecorrenteBruta),
                          Icons.autorenew,
                          detalhe: 'pagamentos recorrentes pagos',
                        ),
                        _indicador(
                          'RECEITA AVULSA',
                          _moeda(_receitaAvulsaBruta),
                          Icons.shopping_bag_outlined,
                          detalhe: 'pagamentos avulsos pagos',
                        ),
                        _indicador(
                          'ESTORNOS',
                          _moeda(_estornos),
                          Icons.undo,
                          detalhe: '${_pct(taxaEstorno)} da receita bruta',
                          cor: _vermelho,
                        ),
                        _indicador(
                          'TICKET MÉDIO',
                          _moeda(_ticketMedio),
                          Icons.receipt_long_outlined,
                          detalhe: 'por pagamento aprovado',
                        ),
                        _indicador(
                          'PAGAMENTOS',
                          _inteiro(_quantidadePagamentos),
                          Icons.check_circle_outline,
                          detalhe: 'pagamentos aprovados no período',
                          cor: _verde,
                        ),
                        _indicador(
                          'USUÁRIOS PAGANTES',
                          _inteiro(_usuariosPagantes.length),
                          Icons.people_alt_outlined,
                          detalhe: 'usuários únicos no período',
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _observacaoDados(),
                    const SizedBox(height: 20),
                    _painel(
                      'Recorrência e previsibilidade',
                      'Indicadores atuais da base de assinaturas e cobranças futuras registradas.',
                      _grade([
                        _indicador(
                          'MRR ESTIMADO',
                          _moeda(_mrrEstimado),
                          Icons.trending_up,
                          detalhe: 'valor mensal das assinaturas ativas',
                          cor: _verde,
                        ),
                        _indicador(
                          'ASSINATURAS ATIVAS',
                          _inteiro(_assinaturasAtivasTotal),
                          Icons.workspace_premium_outlined,
                          detalhe:
                              '${_assinaturasAtivas.length} Efí • ${_assinaturasGoogleAtivas.length} Google',
                        ),
                        _indicador(
                          'PREVISÃO 30 DIAS',
                          _moeda(_receitaPrevistaProximos30Dias),
                          Icons.event_repeat_outlined,
                          detalhe: 'próximas cobranças Efí registradas',
                        ),
                        _indicador(
                          'INADIMPLENTES',
                          _inteiro(_assinaturasInadimplentes),
                          Icons.warning_amber_rounded,
                          detalhe: 'assinaturas com início de inadimplência',
                          cor: _vermelho,
                        ),
                        _indicador(
                          'CANCELAMENTOS',
                          _inteiro(_cancelamentosPeriodo),
                          Icons.cancel_outlined,
                          detalhe: 'assinaturas canceladas no período',
                          cor: _vermelho,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _painel(
                      'Saúde das cobranças recorrentes',
                      'Desempenho das tentativas de cobrança registradas no período.',
                      _grade([
                        _indicador(
                          'COBRANÇAS',
                          _inteiro(_cobrancasRecorrentes),
                          Icons.receipt_outlined,
                        ),
                        _indicador(
                          'APROVADAS',
                          _inteiro(_cobrancasPagas),
                          Icons.check_circle_outline,
                          detalhe: 'taxa ${_pct(taxaAprovacao)}',
                          cor: _verde,
                        ),
                        _indicador(
                          'PENDENTES',
                          _inteiro(_cobrancasPendentes),
                          Icons.schedule,
                        ),
                        _indicador(
                          'RECUSADAS',
                          _inteiro(_cobrancasRecusadas),
                          Icons.credit_card_off_outlined,
                          detalhe: 'taxa ${_pct(taxaRecusa)}',
                          cor: _vermelho,
                        ),
                        _indicador(
                          'CANCELADAS',
                          _inteiro(_cobrancasCanceladas),
                          Icons.block_outlined,
                          cor: _vermelho,
                        ),
                        _indicador(
                          'ESTORNADAS',
                          _inteiro(_cobrancasEstornadas),
                          Icons.undo_outlined,
                          cor: _vermelho,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _painel(
                      'Evolução da receita',
                      'Receita paga por dia dentro do período selecionado.',
                      _evolucaoReceita(),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final duasColunas = constraints.maxWidth >= 900;
                        final a = _painel(
                          'Receita por plano',
                          'Participação dos planos na receita recorrente paga.',
                          _rankingMoeda(_receitaPorPlano),
                        );
                        final b = _painel(
                          'Meios de pagamento',
                          'Quantidade de pagamentos aprovados por método.',
                          _rankingNumero(_pagamentosPorMetodo),
                        );

                        if (!duasColunas) {
                          return Column(
                            children: [
                              a,
                              const SizedBox(height: 20),
                              b,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: a),
                            const SizedBox(width: 20),
                            Expanded(child: b),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final duasColunas = constraints.maxWidth >= 900;
                        final a = _painel(
                          'Bandeiras de cartão',
                          'Distribuição das cobranças pagas que possuem bandeira informada.',
                          _rankingNumero(_pagamentosPorBandeira),
                        );
                        final b = _painel(
                          'Motivos de recusa',
                          'Principais motivos/códigos registrados nas cobranças recusadas.',
                          _rankingNumero(_recusasPorMotivo),
                        );

                        if (!duasColunas) {
                          return Column(
                            children: [
                              a,
                              const SizedBox(height: 20),
                              b,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: a),
                            const SizedBox(width: 20),
                            Expanded(child: b),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final duasColunas = constraints.maxWidth >= 900;
                        final a = _painel(
                          'Receita por tipo de usuário',
                          'Quanto cada perfil de usuário representa na receita paga.',
                          _rankingMoeda(_receitaPorTipoUsuario),
                        );
                        final b = _painel(
                          'Receita por estado',
                          'Distribuição geográfica da receita com base no cadastro do usuário.',
                          _rankingMoeda(_receitaPorEstado),
                        );

                        if (!duasColunas) {
                          return Column(
                            children: [
                              a,
                              const SizedBox(height: 20),
                              b,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: a),
                            const SizedBox(width: 20),
                            Expanded(child: b),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Base consultada: pagamentos recorrentes, pagamentos avulsos, assinaturas Efí, assinaturas Google, pedidos, planos e usuários.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
