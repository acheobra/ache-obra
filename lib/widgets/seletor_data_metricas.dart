import 'package:flutter/material.dart';

/// Seletor de data compartilhado pelas telas de métricas do Ache Obra.

///

/// Ele não usa showDatePicker/CalendarDatePicker. A data é escolhida por

/// dia, mês e ano dentro de um Dialog comum, evitando o problema de

/// renderização do date picker nativo observado no Flutter Web.

class SeletorDataMetricas {
  static const Color _fundo = Color(0xFF1A2C42);

  static const Color _card = Color(0xFF101B2B);

  static const Color _laranja = Color(0xFFFF8C00);

  static const List<String> _meses = <String>[
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  static int _diasNoMes(int ano, int mes) {
    if (mes == 12) {
      return DateTime(ano + 1, 1, 0).day;
    }

    return DateTime(ano, mes + 1, 0).day;
  }

  static DateTime _limitar(
    DateTime data,
    DateTime primeiraData,
    DateTime ultimaData,
  ) {
    final limpa = DateTime(data.year, data.month, data.day);

    final primeira =
        DateTime(primeiraData.year, primeiraData.month, primeiraData.day);

    final ultima = DateTime(ultimaData.year, ultimaData.month, ultimaData.day);

    if (limpa.isBefore(primeira)) return primeira;

    if (limpa.isAfter(ultima)) return ultima;

    return limpa;
  }

  static Future<DateTime?> mostrar(
    BuildContext context, {
    DateTime? dataInicial,
    DateTime? primeiraData,
    DateTime? ultimaData,
    String titulo = 'Selecionar data',
  }) async {
    final agora = DateTime.now();

    final primeira = primeiraData ?? DateTime(2020, 1, 1);

    final ultima = ultimaData ?? DateTime(agora.year + 5, 12, 31);

    DateTime selecionada = _limitar(
      dataInicial ?? agora,
      primeira,
      ultima,
    );

    int dia = selecionada.day;

    int mes = selecionada.month;

    int ano = selecionada.year;

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void ajustarDia() {
              final maximo = _diasNoMes(ano, mes);

              if (dia > maximo) dia = maximo;

              if (dia < 1) dia = 1;
            }

            bool dataPermitida(int d, int m, int a) {
              final valor = DateTime(a, m, d);

              final inicio =
                  DateTime(primeira.year, primeira.month, primeira.day);

              final fim = DateTime(ultima.year, ultima.month, ultima.day);

              return !valor.isBefore(inicio) && !valor.isAfter(fim);
            }

            final dias = List<int>.generate(
              _diasNoMes(ano, mes),
              (index) => index + 1,
            );

            final anos = List<int>.generate(
              ultima.year - primeira.year + 1,
              (index) => primeira.year + index,
            );

            final largura = MediaQuery.sizeOf(context).width;

            final compacto = largura < 560;

            Widget campo<T>({
              required String rotulo,
              required T valor,
              required List<DropdownMenuItem<T>> itens,
              required ValueChanged<T?> onChanged,
            }) {
              return DropdownButtonFormField<T>(
                value: valor,
                isExpanded: true,
                dropdownColor: _card,
                iconEnabledColor: _laranja,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  labelText: rotulo,
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: _fundo,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: _laranja,
                      width: 1.5,
                    ),
                  ),
                ),
                items: itens,
                onChanged: onChanged,
              );
            }

            final campoDia = campo<int>(
              rotulo: 'Dia',
              valor: dia,
              itens: dias
                  .map(
                    (d) => DropdownMenuItem<int>(
                      value: d,
                      child: Text(d.toString().padLeft(2, '0')),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;

                setModalState(() => dia = v);
              },
            );

            final campoMes = campo<int>(
              rotulo: 'Mês',
              valor: mes,
              itens: List<int>.generate(12, (i) => i + 1)
                  .map(
                    (m) => DropdownMenuItem<int>(
                      value: m,
                      child: Text(_meses[m - 1]),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;

                setModalState(() {
                  mes = v;

                  ajustarDia();
                });
              },
            );

            final campoAno = campo<int>(
              rotulo: 'Ano',
              valor: ano,
              itens: anos
                  .map(
                    (a) => DropdownMenuItem<int>(
                      value: a,
                      child: Text(a.toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;

                setModalState(() {
                  ano = v;

                  ajustarDia();
                });
              },
            );

            final dataAtual = DateTime(ano, mes, dia);

            final permitida = dataPermitida(dia, mes, ano);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: Container(
                width: 560,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          color: _laranja,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            titulo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${dia.toString().padLeft(2, '0')}/'
                      '${mes.toString().padLeft(2, '0')}/$ano',
                      style: const TextStyle(
                        color: _laranja,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (compacto)
                      Column(
                        children: [
                          campoDia,
                          const SizedBox(height: 12),
                          campoMes,
                          const SizedBox(height: 12),
                          campoAno,
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(child: campoDia),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: campoMes),
                          const SizedBox(width: 12),
                          Expanded(child: campoAno),
                        ],
                      ),
                    if (!permitida) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'A data escolhida está fora do período permitido.',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text('CANCELAR'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: permitida
                              ? () => Navigator.of(dialogContext).pop(dataAtual)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white12,
                            disabledForegroundColor: Colors.white38,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                          ),
                          icon: const Icon(Icons.check),
                          label: const Text(
                            'CONFIRMAR',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Seletor de data + horário para métricas que precisam de precisão

  /// intradiária, como Engajamento. O método [mostrar] original permanece

  /// inalterado para não afetar as telas que usam somente data.

  static Future<DateTime?> mostrarDataHora(
    BuildContext context, {
    DateTime? dataHoraInicial,
    DateTime? primeiraData,
    DateTime? ultimaData,
    String titulo = 'Selecionar data e horário',
  }) async {
    final agora = DateTime.now();

    final primeira = primeiraData ?? DateTime(2020, 1, 1);

    final ultima = ultimaData ?? DateTime(agora.year + 5, 12, 31, 23, 59);

    DateTime base = dataHoraInicial ?? agora;

    if (base.isBefore(primeira)) base = primeira;

    if (base.isAfter(ultima)) base = ultima;

    int dia = base.day;

    int mes = base.month;

    int ano = base.year;

    int hora = base.hour;

    int minuto = base.minute;

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void ajustarDia() {
              final maximo = _diasNoMes(ano, mes);

              if (dia > maximo) dia = maximo;

              if (dia < 1) dia = 1;
            }

            final dias = List<int>.generate(
              _diasNoMes(ano, mes),
              (index) => index + 1,
            );

            final anos = List<int>.generate(
              ultima.year - primeira.year + 1,
              (index) => primeira.year + index,
            );

            Widget campo<T>({
              required String rotulo,
              required T valor,
              required List<DropdownMenuItem<T>> itens,
              required ValueChanged<T?> onChanged,
            }) {
              return DropdownButtonFormField<T>(
                value: valor,
                isExpanded: true,
                dropdownColor: _card,
                iconEnabledColor: _laranja,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: rotulo,
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: _fundo,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _laranja, width: 1.5),
                  ),
                ),
                items: itens,
                onChanged: onChanged,
              );
            }

            final dataAtual = DateTime(ano, mes, dia, hora, minuto);

            final permitida =
                !dataAtual.isBefore(primeira) && !dataAtual.isAfter(ultima);

            final compacto = MediaQuery.sizeOf(context).width < 650;

            final camposData = <Widget>[
              campo<int>(
                rotulo: 'Dia',
                valor: dia,
                itens: dias
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;

                  setModalState(() => dia = v);
                },
              ),
              campo<int>(
                rotulo: 'Mês',
                valor: mes,
                itens: List<int>.generate(12, (i) => i + 1)
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(_meses[m - 1]),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;

                  setModalState(() {
                    mes = v;

                    ajustarDia();
                  });
                },
              ),
              campo<int>(
                rotulo: 'Ano',
                valor: ano,
                itens: anos
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(a.toString()),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;

                  setModalState(() {
                    ano = v;

                    ajustarDia();
                  });
                },
              ),
            ];

            final camposHora = <Widget>[
              campo<int>(
                rotulo: 'Hora',
                valor: hora,
                itens: List<int>.generate(24, (i) => i)
                    .map((h) => DropdownMenuItem(
                          value: h,
                          child: Text(h.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;

                  setModalState(() => hora = v);
                },
              ),
              campo<int>(
                rotulo: 'Minuto',
                valor: minuto,
                itens: List<int>.generate(60, (i) => i)
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;

                  setModalState(() => minuto = v);
                },
              ),
            ];

            Widget linha(List<Widget> campos) => Row(
                  children: [
                    for (int i = 0; i < campos.length; i++) ...[
                      Expanded(child: campos[i]),
                      if (i < campos.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                );

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                width: 650,
                constraints: const BoxConstraints(maxWidth: 650),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule, color: _laranja),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              titulo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon:
                                const Icon(Icons.close, color: Colors.white60),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${dia.toString().padLeft(2, '0')}/'
                        '${mes.toString().padLeft(2, '0')}/$ano  '
                        '${hora.toString().padLeft(2, '0')}:'
                        '${minuto.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: _laranja,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (compacto) ...[
                        for (final w in camposData) ...[
                          w,
                          const SizedBox(height: 10),
                        ],
                        linha(camposHora),
                      ] else ...[
                        linha(camposData),
                        const SizedBox(height: 12),
                        linha(camposHora),
                      ],
                      if (!permitida) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'A data e o horário escolhidos estão fora do período permitido.',
                          style:
                              TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            child: const Text('CANCELAR'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: permitida
                                ? () =>
                                    Navigator.of(dialogContext).pop(dataAtual)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _laranja,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.check),
                            label: const Text(
                              'CONFIRMAR',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
