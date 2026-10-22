import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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

class CadastroClientePage extends StatefulWidget {
  const CadastroClientePage({super.key});

  @override
  State<CadastroClientePage> createState() => _CadastroClientePageState();
}

class _CadastroClientePageState extends State<CadastroClientePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  File? _arquivoImagemSelecionado; // Para mobile (Android/iOS)
  Uint8List? _bytesImagemSelecionada; // Para Web

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

  final List<String> _listaGeneros = [
    'Masculino',
    'Feminino',
    'Outro',
    'Empresa'
  ];

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

  String? _estadoSelecionado;
  String? _cidadeSelecionada;
  String? _generoSelecionado;
  String _tipoDocumento = 'cpf';
  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _isLoading = false;
  bool _aceitouTermos = false;
  bool _permanecerConectado = true;
  bool _senhaOculta = true;

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
        origem: 'Leitura dos Termos (PDF) - Cliente',
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
      origem: 'Busca de Cidades no Cadastro (Cliente)',
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

  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _bytesImagemSelecionada = bytes;
        });
      } else {
        setState(() {
          _arquivoImagemSelecionado = File(pickedFile.path);
        });
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _cnpjController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
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

    final cpf = _cpfController.text.trim();
    final cnpj = _cnpjController.text.trim();

    if (cpf.isEmpty && cnpj.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Informe o CPF ou o CNPJ!'),
          backgroundColor: Colors.orange));
      return;
    }

    if (cpf.isNotEmpty && cnpj.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preencha apenas um documento: CPF ou CNPJ.'),
          backgroundColor: Colors.orange));
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

      // Verificação de CPF duplicado
      if (cpf.isNotEmpty) {
        final queryCpf = await supabase
            .from('tab_usuarios')
            .select('usuario_tipo')
            .eq('cpf', cpf)
            .maybeSingle();

        if (queryCpf != null) {
          final tipoUsuario = queryCpf['usuario_tipo'] ?? 'usuário';

          DiscordLogger.enviarErro(
            origem: 'Cadastro Cliente - CPF Duplicado',
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

      // Verificação de CNPJ duplicado
      if (cnpj.isNotEmpty) {
        final queryCnpj = await supabase
            .from('tab_usuarios')
            .select('usuario_tipo')
            .eq('cnpj', cnpj)
            .maybeSingle();

        if (queryCnpj != null) {
          final tipoUsuario = queryCnpj['usuario_tipo'] ?? 'usuário';

          DiscordLogger.enviarErro(
            origem: 'Cadastro Cliente - CNPJ Duplicado',
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

      // 1. Criação do usuário no Supabase Auth
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

      // Bloco de gravação do banco/storage (faz logout em caso de erro)
      try {
        String? fotoUrl;

        // 2. Upload da foto se houver uma selecionada
        if (_arquivoImagemSelecionado != null ||
            _bytesImagemSelecionada != null) {
          final fileName =
              'perfil_${userIdCriado}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final path = 'public/$fileName';

          if (kIsWeb) {
            await supabase.storage.from('fotos_perfil').uploadBinary(
                  path,
                  _bytesImagemSelecionada!,
                  fileOptions: const FileOptions(upsert: true),
                );
          } else {
            await supabase.storage.from('fotos_perfil').upload(
                  path,
                  _arquivoImagemSelecionado!,
                  fileOptions: const FileOptions(upsert: true),
                );
          }

          fotoUrl = supabase.storage.from('fotos_perfil').getPublicUrl(path);
        }

        String whatsappLimpo =
            _whatsappController.text.replaceAll(RegExp(r'[^0-9]'), '');

        const String categoriaUsuario = 'cliente';

        // 3. Busca o ID do plano grátis correspondente
        final planoResponse = await supabase
            .from('tab_planos')
            .select('id')
            .eq('nome_plano', '$categoriaUsuario-gratis')
            .maybeSingle();

        String? planoId;
        if (planoResponse != null) {
          planoId = planoResponse['id'];
        }

        // 4. Gravação na tabela tab_usuarios salvando em whatsapp e telefone
        await supabase.from('tab_usuarios').upsert({
          'id': userIdCriado,
          'usuario_nome': nomeMaiusculo,
          'cpf': cpf.isNotEmpty ? cpf : null,
          'cnpj': cnpj.isNotEmpty ? cnpj : null,
          'genero': _generoSelecionado,
          'whatsapp': whatsappLimpo,
          'telefone': whatsappLimpo,
          'email': emailTexto,
          'estado': _estadoSelecionado,
          'cidade': _cidadeSelecionada,
          'plano_id': planoId,
          'foto_url': fotoUrl,
          'usuario_status': 'ativo',
          'usuario_tipo': categoriaUsuario,
          'email_verificado': false,
          'whatsapp_verificado': false,
          'dt_cadastro': DateTime.now().toIso8601String(),
        });

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
        origem: 'Cadastro de Cliente',
        erro: error,
        email: emailTexto,
      );

      if (mounted) {
        String mensagemErro;

        if (error is PostgrestException) {
          mensagemErro =
              'Erro de Permissão/Banco (${error.code}): ${error.message}';
        } else if (error is AuthException) {
          if (error.message.contains('user_already_exists') ||
              error.message.contains('User already registered')) {
            mensagemErro = 'E-mail já cadastrado, tente outro!';
          } else {
            mensagemErro = 'Erro de Autenticação: ${error.message}';
          }
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
          'CADASTRO DE CLIENTE',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white24,
                        backgroundImage: _bytesImagemSelecionada != null
                            ? MemoryImage(_bytesImagemSelecionada!)
                            : (_arquivoImagemSelecionado != null
                                ? FileImage(_arquivoImagemSelecionado!)
                                    as ImageProvider
                                : null),
                        child: (_arquivoImagemSelecionado == null &&
                                _bytesImagemSelecionada == null)
                            ? Icon(Icons.person, size: 40, color: _primaryColor)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _selecionarImagem,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Toque na câmera para adicionar foto",
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 12),
                _buildTextFormField(
                  controller: _nomeController,
                  label: 'NOME COMPLETO',
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
                      return 'Informe seu nome completo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DOCUMENTO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Escolha uma opção. É necessário informar somente CPF ou CNPJ.',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const SizedBox(
                                width: double.infinity,
                                child: Text(
                                  'PESSOA FÍSICA - CPF',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              selected: _tipoDocumento == 'cpf',
                              selectedColor: _primaryColor,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _tipoDocumento == 'cpf'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _tipoDocumento = 'cpf';
                                  _cnpjController.clear();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const SizedBox(
                                width: double.infinity,
                                child: Text(
                                  'EMPRESA - CNPJ',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              selected: _tipoDocumento == 'cnpj',
                              selectedColor: _primaryColor,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _tipoDocumento == 'cnpj'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _tipoDocumento = 'cnpj';
                                  _cpfController.clear();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_tipoDocumento == 'cpf')
                  _buildTextFormField(
                    controller: _cpfController,
                    label: 'CPF',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_maskCpf],
                    validator: (value) {
                      final cpfTrim = value?.trim() ?? '';
                      final numerosCpf =
                          cpfTrim.replaceAll(RegExp(r'[^0-9]'), '');

                      if (cpfTrim.isEmpty) {
                        return 'Informe o CPF';
                      }
                      if (numerosCpf.length != 11) {
                        return 'O CPF deve conter exatamente 11 números';
                      }
                      if (!_validarCpf(cpfTrim)) {
                        return 'CPF inválido';
                      }
                      return null;
                    },
                  ),
                if (_tipoDocumento == 'cnpj')
                  _buildTextFormField(
                    controller: _cnpjController,
                    label: 'CNPJ',
                    icon: Icons.business_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_maskCnpj],
                    validator: (value) {
                      final cnpjTrim = value?.trim() ?? '';
                      final numerosCnpj =
                          cnpjTrim.replaceAll(RegExp(r'[^0-9]'), '');

                      if (cnpjTrim.isEmpty) {
                        return 'Informe o CNPJ';
                      }
                      if (numerosCnpj.length != 14) {
                        return 'O CNPJ deve conter exatamente 14 números';
                      }
                      if (!_validarCnpj(cnpjTrim)) {
                        return 'CNPJ inválido';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'GÊNERO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.wc, color: _primaryColor),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'ESTADO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.map, color: _primaryColor),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
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
                const SizedBox(height: 10),
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
                                    ? 'SELECIONE O ESTADO PRIMEIRA'
                                    : 'DIGITE OU SELECIONE A CIDADE'),
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon:
                                Icon(Icons.location_city, color: _primaryColor),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
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
                            // A cidade só é considerada válida depois que o
                            // usuário toca em uma opção da lista do Autocomplete.
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
                const SizedBox(height: 10),
                _buildTextFormField(
                  controller: _whatsappController,
                  label: 'TELEFONE/WHATSAPP',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_maskWhatsapp],
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
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
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
                      return 'A senha deve ter entre 4 e 8 dígitos';
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                    title: const Text('Permanecer conectado',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: _permanecerConectado,
                    onChanged: (val) =>
                        setState(() => _permanecerConectado = val!),
                    activeColor: _primaryColor,
                    dense: true),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _aceitouTermos,
                    onChanged: (val) => setState(() => _aceitouTermos = val!),
                    activeColor: _primaryColor,
                    dense: true,
                    title: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Li e aceito os ',
                            style:
                                TextStyle(color: Colors.white, fontSize: 13)),
                        InkWell(
                          onTap: _abrirTermos,
                          child: Text(
                            'termos de uso',
                            style: TextStyle(
                              color: _primaryColor,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _realizarCadastro,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('CRIAR CONTA DE CLIENTE',
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
