import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pages/feed_page.dart';

class DiscordLogger {
  static const String _webhookUrl =
      'https://discord.com/api/webhooks/1539960415960834139/4eQduRq4xoQnP4lCwOUBXXVDxyUGL-wXmDvXNJr7x9Niy9JjHkHqXmAOXNei9rNP74rD';

  static Future<void> enviarErro({
    required String origem,
    required Object erro,
    String? email,
  }) async {
    if (_webhookUrl.isEmpty) return;

    try {
      final payload = {
        "embeds": [
          {
            "title": "🚨 Falha Registrada - $origem",
            "color": 16711680,
            "fields": [
              {
                "name": "E-mail Tentado",
                "value":
                    email != null && email.isNotEmpty ? email : "Não informado",
                "inline": true
              },
              {"name": "Origem", "value": origem, "inline": true},
              {
                "name": "Detalhes do Erro",
                "value": "```$erro```",
                "inline": false
              }
            ],
            "timestamp": DateTime.now().toUtc().toIso8601String(),
          }
        ]
      };

      await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint("Erro ao enviar log para o Discord: $e");
    }
  }
}

class CadastroProfissionalPage extends StatefulWidget {
  const CadastroProfissionalPage({super.key});

  @override
  State<CadastroProfissionalPage> createState() =>
      _CadastroProfissionalPageState();
}

class _CadastroProfissionalPageState extends State<CadastroProfissionalPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _nascimentoController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _especializacaoController = TextEditingController();

  final List<String> _listaGeneros = [
    'Masculino',
    'Feminino',
    'Outro',
    'Empresa'
  ];
  String? _generoSelecionado;
  String? _tipoDocumentoSelecionado;

  final _maskNascimento = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final _maskSenha = MaskTextInputFormatter(
    mask: '########',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final _maskWhatsapp = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final _maskCpf = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final _maskCnpj = MaskTextInputFormatter(
    mask: '##.###.###/####-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final List<String> _listaEstados = [
    "AC",
    "AL",
    "AM",
    "AP",
    "BA",
    "CE",
    "DF",
    "ES",
    "GO",
    "MA",
    "MG",
    "MS",
    "MT",
    "PA",
    "PB",
    "PE",
    "PI",
    "PR",
    "RJ",
    "RN",
    "RO",
    "RR",
    "RS",
    "SC",
    "SE",
    "SP",
    "TO"
  ];

  String? _estadoSelecionado;
  String? _cidadeSelecionada;
  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _isLoading = false;
  bool _aceitouTermos = false;
  bool _permanecerConectado = true;
  bool _senhaOculta = true;

  bool _fazTudo = false;
  bool _impermeabilizador = false;
  bool _encanador = false;
  bool _eletricista = false;
  bool _pintorIndustrial = false;
  bool _telhadista = false;
  bool _carpinteiro = false;
  bool _jardineiro = false;
  bool _vidraceiro = false;
  bool _serralheiro = false;
  bool _azulejista = false;
  bool _instaladorAr = false;
  bool _gesseiro = false;
  bool _pedreiro = false;
  bool _pintor = false;
  bool _mestreObras = false;

  final Color _bgColor = const Color(0xFF1A2C42);
  final Color _primaryColor = const Color(0xFFFF8C00);

  Future<void> _abrirTermos() async {
    try {
      if (kIsWeb) {
        final Uri url = Uri.parse('assets/termos.pdf');
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw 'Não foi possível abrir o PDF no navegador.';
        }
      } else {
        final byteData = await rootBundle.load('assets/termos.pdf');
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/termos.pdf');
        await file.writeAsBytes(
          byteData.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      DiscordLogger.enviarErro(
        origem: 'Leitura dos Termos (PDF) - Profissional',
        erro: e,
        email: _emailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir o arquivo dos termos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _buscarCidades(String estado) async {
    final String estadoConsulta = estado.trim().toUpperCase();

    if (estadoConsulta.isEmpty) return;

    if (mounted) {
      setState(() {
        _carregandoCidades = true;
        _listaCidades = [];
        _cidadeSelecionada = null;
      });
    }

    Object? ultimoErro;

    // Um 504 do PostgREST pode ser transitório. Tenta novamente antes de
    // registrar a falha e evita inundar o Discord com falhas momentâneas.
    for (int tentativa = 1; tentativa <= 3; tentativa++) {
      try {
        final data = await Supabase.instance.client
            .from('tab_localidades')
            .select('municipio')
            .eq('estado', estadoConsulta)
            .order('municipio', ascending: true)
            .timeout(const Duration(seconds: 15));

        final cidades = (data as List)
            .map((e) => e['municipio']?.toString().trim() ?? '')
            .where((cidade) => cidade.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        // Se o usuário mudou o estado enquanto a consulta estava em andamento,
        // ignora a resposta antiga para não misturar cidades de estados.
        if (!mounted || _estadoSelecionado != estadoConsulta) return;

        setState(() {
          _listaCidades = cidades;
          _carregandoCidades = false;
        });
        return;
      } catch (e) {
        ultimoErro = e;
        debugPrint(
          'Erro ao buscar cidades de $estadoConsulta '
          '(tentativa $tentativa/3): $e',
        );

        if (tentativa < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 700 * tentativa),
          );
          if (!mounted || _estadoSelecionado != estadoConsulta) return;
        }
      }
    }

    if (!mounted || _estadoSelecionado != estadoConsulta) return;

    setState(() {
      _carregandoCidades = false;
      _listaCidades = [];
      _cidadeSelecionada = null;
    });

    await DiscordLogger.enviarErro(
      origem: 'Busca de Cidades no Cadastro (Profissional)',
      erro: ultimoErro ?? 'Falha desconhecida ao buscar cidades',
      email: _emailController.text.trim(),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Não foi possível carregar as cidades de $estadoConsulta. '
          'Tente selecionar o estado novamente em alguns segundos.',
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _selecionarDataNascimento() async {
    DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: _primaryColor,
            colorScheme: ColorScheme.light(primary: _primaryColor),
            buttonTheme:
                const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (dataEscolhida != null) {
      String dia = dataEscolhida.day.toString().padLeft(2, '0');
      String mes = dataEscolhida.month.toString().padLeft(2, '0');
      String ano = dataEscolhida.year.toString();

      setState(() {
        _nascimentoController.text = '$dia/$mes/$ano';
      });
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _cnpjController.dispose();
    _nascimentoController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _especializacaoController.dispose();
    super.dispose();
  }

  bool _validarCpf(String cpf) {
    cpf = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpf.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

    var soma = 0;
    for (int i = 0; i < 9; i++) {
      soma += int.parse(cpf[i]) * (10 - i);
    }
    var resto = 11 - (soma % 11);
    var digito1 = (resto == 10 || resto == 11) ? 0 : resto;
    if (digito1 != int.parse(cpf[9])) return false;

    soma = 0;
    for (int i = 0; i < 10; i++) {
      soma += int.parse(cpf[i]) * (11 - i);
    }
    resto = 11 - (soma % 11);
    var digito2 = (resto == 10 || resto == 11) ? 0 : resto;
    if (digito2 != int.parse(cpf[10])) return false;

    return true;
  }

  bool _validarCnpj(String cnpj) {
    cnpj = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
    if (cnpj.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(cnpj)) return false;

    List<int> pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    List<int> pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    var soma = 0;
    for (int i = 0; i < 12; i++) {
      soma += int.parse(cnpj[i]) * pesos1[i];
    }
    var resto = soma % 11;
    var digito1 = resto < 2 ? 0 : 11 - resto;
    if (digito1 != int.parse(cnpj[12])) return false;

    soma = 0;
    for (int i = 0; i < 13; i++) {
      soma += int.parse(cnpj[i]) * pesos2[i];
    }
    resto = soma % 11;
    var digito2 = resto < 2 ? 0 : 11 - resto;
    if (digito2 != int.parse(cnpj[13])) return false;

    return true;
  }

  Future<void> _realizarCadastro() async {
    if (!_aceitouTermos ||
        _estadoSelecionado == null ||
        _cidadeSelecionada == null ||
        _generoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Preencha todos os campos obrigatórios e aceite os termos!'),
          backgroundColor: Colors.orange));
      return;
    }

    if (_tipoDocumentoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione PESSOA FÍSICA - CPF ou EMPRESA - CNPJ!'),
          backgroundColor: Colors.orange));
      return;
    }

    final cpf = _cpfController.text.trim();
    final cnpj = _cnpjController.text.trim();

    if (_tipoDocumentoSelecionado == 'cpf' && cpf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Informe o CPF!'), backgroundColor: Colors.orange));
      return;
    }

    if (_tipoDocumentoSelecionado == 'cnpj' && cnpj.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Informe o CNPJ!'), backgroundColor: Colors.orange));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final senhaTexto = _senhaController.text.trim();
    final emailTexto = _emailController.text.trim();
    final regexApenasNumeros = RegExp(r'^[0-9]+$');
    if (!regexApenasNumeros.hasMatch(senhaTexto) ||
        senhaTexto.length < 4 ||
        senhaTexto.length > 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A senha deve conter apenas números e ter entre 4 e 8 caracteres!'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      if (cpf.isNotEmpty) {
        final queryCpf = await supabase
            .from('tab_usuarios')
            .select('usuario_tipo')
            .eq('cpf', cpf)
            .maybeSingle();

        if (queryCpf != null) {
          final tipoUsuario = queryCpf['usuario_tipo'] ?? 'usuário';

          DiscordLogger.enviarErro(
            origem: 'Cadastro Profissional - CPF Duplicado',
            erro: 'CPF $cpf já cadastrado como $tipoUsuario',
            email: emailTexto,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Este cpf já está cadastrado como "$tipoUsuario"'),
                backgroundColor: Colors.red));
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      if (cnpj.isNotEmpty) {
        final queryCnpj = await supabase
            .from('tab_usuarios')
            .select('usuario_tipo')
            .eq('cnpj', cnpj)
            .maybeSingle();

        if (queryCnpj != null) {
          final tipoUsuario = queryCnpj['usuario_tipo'] ?? 'usuário';

          DiscordLogger.enviarErro(
            origem: 'Cadastro Profissional - CNPJ Duplicado',
            erro: 'CNPJ $cnpj já cadastrado como $tipoUsuario',
            email: emailTexto,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Este cnpj já está cadastrado como "$tipoUsuario"'),
                backgroundColor: Colors.red));
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      final nomeMaiusculo = _nomeController.text.trim().toUpperCase();

      // Registra a conta no Supabase Auth
      final AuthResponse response = await supabase.auth.signUp(
        email: emailTexto,
        password: senhaTexto,
        data: {'nome': nomeMaiusculo},
      );

      final user = response.user;
      if (user == null) {
        throw 'Não foi possível registrar o usuário na autenticação.';
      }

      final String userIdCriado = user.id;

      // Bloco de gravação do banco de dados (se falhar, faz logout e interrompe)
      try {
        String dataNascimentoFormatada = '';
        if (_nascimentoController.text.trim().length == 10) {
          List<String> partes = _nascimentoController.text.trim().split('/');
          if (partes.length == 3) {
            dataNascimentoFormatada = '${partes[2]}-${partes[1]}-${partes[0]}';
          }
        }

        String whatsappLimpo =
            _whatsappController.text.replaceAll(RegExp(r'[^0-9]'), '');

        const String categoriaUsuario = 'profissional';

        final planoResponse = await supabase
            .from('tab_planos')
            .select('id')
            .eq('nome_plano', '$categoriaUsuario-gratis')
            .maybeSingle();

        String? planoId;
        if (planoResponse != null) {
          planoId = planoResponse['id'];
        }

        // SALVA O NÚMERO EM 'whatsapp' E TAMBÉM EM 'telefone'
        await supabase.from('tab_usuarios').upsert({
          'id': userIdCriado,
          'usuario_nome': nomeMaiusculo,
          'cpf': cpf.isNotEmpty ? cpf : null,
          'cnpj': cnpj.isNotEmpty ? cnpj : null,
          'genero': _generoSelecionado,
          'dt_nascimento': dataNascimentoFormatada.isNotEmpty
              ? dataNascimentoFormatada
              : null,
          'whatsapp': whatsappLimpo,
          'telefone': whatsappLimpo,
          'email': emailTexto,
          'estado': _estadoSelecionado,
          'cidade': _cidadeSelecionada,
          'especializacao': _especializacaoController.text.trim(),
          'plano_id': planoId,
          'usuario_status': 'ativo',
          'usuario_tipo': categoriaUsuario,
          'email_verificado': false,
          'whatsapp_verificado': false,
          'dt_cadastro': DateTime.now().toIso8601String(),
        });

        final Map<String, bool> mapaProfissoes = {
          'Faz Tudo': _fazTudo,
          'Impermeabilizador': _impermeabilizador,
          'Encanador (Hidráulico)': _encanador,
          'Eletricista': _eletricista,
          'Pintor Industrial': _pintorIndustrial,
          'Telhadista': _telhadista,
          'Carpinteiro': _carpinteiro,
          'Jardineiro': _jardineiro,
          'Vidraceiro': _vidraceiro,
          'Serralheiro': _serralheiro,
          'Azulejista': _azulejista,
          'Instalador de Ar Condicionado': _instaladorAr,
          'Gesseiro': _gesseiro,
          'Pedreiro': _pedreiro,
          'Pintor': _pintor,
          'Mestre de Obras': _mestreObras,
        };

        final List<dynamic> catalogoProfissoes =
            await supabase.from('tab_profissoes').select('id, profissao_nome');

        for (var entry in mapaProfissoes.entries) {
          String nomeProfissao = entry.key;
          bool selecionada = entry.value;

          if (selecionada) {
            final match = catalogoProfissoes.firstWhere(
              (p) =>
                  p['profissao_nome'].toString().trim().toLowerCase() ==
                  nomeProfissao.toLowerCase(),
              orElse: () => <String, dynamic>{},
            );

            if (match.isNotEmpty) {
              String profissaoId = match['id'];

              await supabase.from('tab_usuarios_profissoes').insert({
                'usuario_id': userIdCriado,
                'profissao_id': profissaoId,
              });
            }
          }
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FeedPage()),
          );
        }
      } catch (dbError) {
        await supabase.auth.signOut();
        rethrow;
      }
    } catch (error) {
      DiscordLogger.enviarErro(
        origem: 'Cadastro de Profissional',
        erro: error,
        email: emailTexto,
      );

      if (mounted) {
        String mensagemErro;

        if (error is PostgrestException) {
          mensagemErro =
              'Erro de Permissão/Banco (${error.code}): ${error.message}';
        } else if (error is AuthException) {
          mensagemErro = 'Erro de Autenticação: ${error.message}';
        } else {
          mensagemErro = 'Erro: $error';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensagemErro),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _primaryColor),
        title: const Text(
          'CADASTRO DE PROFISSIONAL',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Icon(Icons.badge_outlined,
                      size: 64, color: _primaryColor),
                ),
                const SizedBox(height: 20),
                _buildTextFormField(
                  controller: _nomeController,
                  label: 'NOME COMPLETO / EMPRESA',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => TextEditingValue(
                        text: newValue.text.toUpperCase(),
                        selection: newValue.selection,
                      ),
                    ),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe seu nome ou o nome da empresa';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'TIPO DE CADASTRO\nEscolha uma opção. É necessário informar somente CPF ou CNPJ.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _tipoDocumentoSelecionado,
                  decoration: InputDecoration(
                    labelText: 'CPF OU CNPJ',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon:
                        Icon(Icons.badge_outlined, color: _primaryColor),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'cpf',
                      child: Text(
                        'PESSOA FÍSICA - CPF',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'cnpj',
                      child: Text(
                        'EMPRESA - CNPJ',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _tipoDocumentoSelecionado = value;
                      if (value == 'cpf') {
                        _cnpjController.clear();
                      } else if (value == 'cnpj') {
                        _cpfController.clear();
                      }
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Selecione CPF ou CNPJ' : null,
                ),
                const SizedBox(height: 16),
                if (_tipoDocumentoSelecionado == 'cpf')
                  TextFormField(
                    controller: _cpfController,
                    inputFormatters: [_maskCpf],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black),
                    validator: (value) {
                      if (_tipoDocumentoSelecionado != 'cpf') return null;
                      final cpfTrim = value?.trim() ?? '';
                      final numerosCpf =
                          cpfTrim.replaceAll(RegExp(r'[^0-9]'), '');
                      if (cpfTrim.isEmpty) return 'Informe o CPF';
                      if (numerosCpf.length != 11) {
                        return 'O CPF deve conter exatamente 11 números';
                      }
                      if (!_validarCpf(cpfTrim)) return 'CPF inválido';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'CPF - PESSOA FÍSICA',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon:
                          Icon(Icons.badge_outlined, color: _primaryColor),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                if (_tipoDocumentoSelecionado == 'cnpj')
                  TextFormField(
                    controller: _cnpjController,
                    inputFormatters: [_maskCnpj],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black),
                    validator: (value) {
                      if (_tipoDocumentoSelecionado != 'cnpj') return null;
                      final cnpjTrim = value?.trim() ?? '';
                      final numerosCnpj =
                          cnpjTrim.replaceAll(RegExp(r'[^0-9]'), '');
                      if (cnpjTrim.isEmpty) return 'Informe o CNPJ';
                      if (numerosCnpj.length != 14) {
                        return 'O CNPJ deve conter exatamente 14 números';
                      }
                      if (!_validarCnpj(cnpjTrim)) return 'CNPJ inválido';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'CNPJ - EMPRESA',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon:
                          Icon(Icons.business_outlined, color: _primaryColor),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'GÊNERO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.wc, color: _primaryColor),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12))),
                  value: _generoSelecionado,
                  items: _listaGeneros
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e,
                              style: const TextStyle(color: Colors.black))))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _generoSelecionado = value),
                  validator: (value) =>
                      value == null ? 'Selecione o gênero' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nascimentoController,
                  inputFormatters: [_maskNascimento],
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'DATA DE NASCIMENTO (DD/MM/AAAA)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon:
                        Icon(Icons.calendar_today, color: _primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.date_range, color: _primaryColor),
                      onPressed: _selecionarDataNascimento,
                      tooltip: 'Abrir Calendário',
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'ESTADO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.map, color: _primaryColor),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12))),
                  items: _listaEstados
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e,
                              style: const TextStyle(color: Colors.black))))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      final estado = value.trim().toUpperCase();
                      setState(() {
                        _estadoSelecionado = estado;
                        _cidadeSelecionada = null;
                      });
                      _buscarCidades(estado);
                    }
                  },
                  validator: (value) =>
                      value == null ? 'Selecione um estado' : null,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<String>(
                      key: ValueKey(_estadoSelecionado),
                      initialValue: TextEditingValue(
                        text: _cidadeSelecionada ?? '',
                      ),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _listaCidades;
                        }
                        return _listaCidades.where((String cidade) {
                          return cidade.toLowerCase().startsWith(
                                textEditingValue.text.toLowerCase(),
                              );
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          _cidadeSelecionada = selection;
                        });
                      },
                      fieldViewBuilder: (context, textEditingController,
                          focusNode, onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          enabled:
                              !_carregandoCidades && _estadoSelecionado != null,
                          style: const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            labelText: _carregandoCidades
                                ? 'CARREGANDO CIDADES...'
                                : (_estadoSelecionado == null
                                    ? 'SELECIONE O ESTADO PRIMEIRO'
                                    : 'DIGITE OU SELECIONE A CIDADE'),
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon:
                                Icon(Icons.location_city, color: _primaryColor),
                            suffixIcon: _carregandoCidades
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (value) {
                            // O texto digitado serve somente para pesquisar.
                            // A cidade só é válida quando o usuário seleciona
                            // uma opção exibida pelo Autocomplete.
                            if (_cidadeSelecionada != null &&
                                value != _cidadeSelecionada) {
                              setState(() {
                                _cidadeSelecionada = null;
                              });
                            }
                          },
                          validator: (value) {
                            if (_cidadeSelecionada == null ||
                                _cidadeSelecionada!.isEmpty) {
                              return 'Selecione uma cidade válida da lista';
                            }
                            return null;
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                                maxHeight: 200,
                              ),
                              color: Colors.white,
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option =
                                      options.elementAt(index);
                                  return ListTile(
                                    title: Text(
                                      option,
                                      style:
                                          const TextStyle(color: Colors.black),
                                    ),
                                    onTap: () {
                                      onSelected(option);
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _whatsappController,
                  inputFormatters: [_maskWhatsapp],
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.black),
                  validator: (value) {
                    final numeros =
                        value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                    if (numeros.isEmpty) {
                      return 'Informe o número do telefone/WhatsApp';
                    }
                    if (numeros.length != 11) {
                      return 'O telefone/WhatsApp deve conter exatamente 11 números';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'TELEFONE/WHATSAPP',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.phone_android, color: _primaryColor),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _emailController,
                  label: 'E-MAIL',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o e-mail';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Informe um e-mail válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaController,
                  inputFormatters: [_maskSenha],
                  keyboardType: TextInputType.number,
                  obscureText: _senhaOculta,
                  style: const TextStyle(color: Colors.black),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe a senha';
                    }
                    if (value.length < 4 || value.length > 8) {
                      return 'A senha deve ter entre 4 e 8 caracteres';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'SENHA (APENAS NÚMEROS, 4 A 8 DÍGITOS)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.lock_outline, color: _primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaOculta ? Icons.visibility_off : Icons.visibility,
                        color: _primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _senhaOculta = !_senhaOculta;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _especializacaoController,
                  keyboardType: TextInputType.multiline,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'ESPECIALIDADES / DETALHES DOS SERVIÇOS',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: Icon(Icons.description_outlined,
                          color: _primaryColor),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SELECIONE SUAS ATUAÇÕES:',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildCheckboxTile('Faz Tudo', _fazTudo,
                    (val) => setState(() => _fazTudo = val)),
                _buildCheckboxTile('Impermeabilizador', _impermeabilizador,
                    (val) => setState(() => _impermeabilizador = val)),
                _buildCheckboxTile('Encanador (Hidráulico)', _encanador,
                    (val) => setState(() => _encanador = val)),
                _buildCheckboxTile('Eletricista', _eletricista,
                    (val) => setState(() => _eletricista = val)),
                _buildCheckboxTile('Pintor Industrial', _pintorIndustrial,
                    (val) => setState(() => _pintorIndustrial = val)),
                _buildCheckboxTile('Telhadista', _telhadista,
                    (val) => setState(() => _telhadista = val)),
                _buildCheckboxTile('Carpinteiro', _carpinteiro,
                    (val) => setState(() => _carpinteiro = val)),
                _buildCheckboxTile('Jardineiro', _jardineiro,
                    (val) => setState(() => _jardineiro = val)),
                _buildCheckboxTile('Vidraceiro', _vidraceiro,
                    (val) => setState(() => _vidraceiro = val)),
                _buildCheckboxTile('Serralheiro', _serralheiro,
                    (val) => setState(() => _serralheiro = val)),
                _buildCheckboxTile('Azulejista', _azulejista,
                    (val) => setState(() => _azulejista = val)),
                _buildCheckboxTile(
                    'Instalador de Ar Condicionado',
                    _instaladorAr,
                    (val) => setState(() => _instaladorAr = val)),
                _buildCheckboxTile('Gesseiro', _gesseiro,
                    (val) => setState(() => _gesseiro = val)),
                _buildCheckboxTile('Pedreiro', _pedreiro,
                    (val) => setState(() => _pedreiro = val)),
                _buildCheckboxTile(
                    'Pintor', _pintor, (val) => setState(() => _pintor = val)),
                _buildCheckboxTile('Mestre de Obras', _mestreObras,
                    (val) => setState(() => _mestreObras = val)),
                const SizedBox(height: 20),
                CheckboxListTile(
                    title: const Text('Permanecer conectado',
                        style: TextStyle(color: Colors.white)),
                    value: _permanecerConectado,
                    onChanged: (val) =>
                        setState(() => _permanecerConectado = val!),
                    activeColor: _primaryColor),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _aceitouTermos,
                    onChanged: (val) => setState(() => _aceitouTermos = val!),
                    activeColor: _primaryColor,
                    title: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Li e aceito os ',
                            style: TextStyle(color: Colors.white)),
                        InkWell(
                          onTap: _abrirTermos,
                          child: Text(
                            'termos de uso',
                            style: TextStyle(
                              color: _primaryColor,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    )),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _realizarCadastro,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('CRIAR CONTA PROFISSIONAL',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxTile(
      String title, bool value, Function(bool) onChanged) {
    return CheckboxListTile(
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: value,
      onChanged: (val) {
        bool novoValor = val ?? false;
        if (novoValor) {
          final listProfissoes = [
            _fazTudo,
            _impermeabilizador,
            _encanador,
            _eletricista,
            _pintorIndustrial,
            _telhadista,
            _carpinteiro,
            _jardineiro,
            _vidraceiro,
            _serralheiro,
            _azulejista,
            _instaladorAr,
            _gesseiro,
            _pedreiro,
            _pintor,
            _mestreObras,
          ];

          int totalAtuais = listProfissoes.where((p) => p).length;

          if (totalAtuais >= 1) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Você poderá escolher mais profissões quando terminar o cadastro'),
              backgroundColor: Colors.orange,
            ));
            return;
          }
        }
        onChanged(novoValor);
      },
      activeColor: _primaryColor,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: _primaryColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
