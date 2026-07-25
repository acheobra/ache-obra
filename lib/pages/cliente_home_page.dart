import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart';

class ClienteHomePage extends StatefulWidget {
  const ClienteHomePage({super.key});

  @override
  State<ClienteHomePage> createState() => _ClienteHomePageState();
}

class _ClienteHomePageState extends State<ClienteHomePage> {
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _whatsappController = TextEditingController();

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
  String _nomeExibicao = "";
  String? _fotoUrl;
  File? _novaImagemArquivo;
  bool _enviandoFoto = false;

  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _verificandoAcesso = true;

  @override
  void initState() {
    super.initState();
    _verificarAcessoCarregarDados();
  }

  Future<void> _verificarAcessoCarregarDados() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      _redirecionarLogin();
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('tab_usuarios')
          .select()
          .eq('id', user.id)
          .single();

      final tipoUsuario = data['tipo'] ?? 'cliente';

      if (tipoUsuario.toString().toLowerCase() != 'cliente') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Acesso restrito apenas para contas de clientes!"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        _redirecionarLogin();
        return;
      }

      setState(() {
        _nomeController.text = data['usuario_nome'] ?? '';
        _nomeExibicao = data['usuario_nome'] ?? 'Cliente';
        _emailController.text = data['email'] ?? '';
        _whatsappController.text = data['whatsapp'] ?? '';
        _estadoSelecionado = data['estado'];
        _cidadeSelecionada = data['cidade'];
        _fotoUrl = data['foto_url'];
        _verificandoAcesso = false;
      });

      if (_estadoSelecionado != null) {
        await _buscarCidades(_estadoSelecionado!, manterCidadeAtual: true);
      }
    } catch (e) {
      debugPrint('Erro ao verificar acesso do cliente: $e');
      _redirecionarLogin();
    }
  }

  void _redirecionarLogin() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AcheObraHome()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _selecionarEEnviarFoto() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile == null) return;

    setState(() {
      _novaImagemArquivo = File(pickedFile.path);
      _enviandoFoto = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      const bucketName =
          'fotos_perfil'; // Corrigido para o nome exato do bucket

      await Supabase.instance.client.storage
          .from(bucketName)
          .upload(fileName, _novaImagemArquivo!);

      final publicUrl = Supabase.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('tab_usuarios')
          .update({'foto_url': publicUrl}).eq('id', user.id);

      setState(() {
        _fotoUrl = publicUrl;
        _enviandoFoto = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Foto de perfil atualizada com sucesso!")),
        );
      }
    } catch (e) {
      setState(() => _enviandoFoto = false);
      debugPrint('Erro ao enviar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erro ao enviar foto: $e"),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _buscarCidades(String estado,
      {bool manterCidadeAtual = false}) async {
    setState(() {
      _carregandoCidades = true;
      if (!manterCidadeAtual) {
        _cidadeSelecionada = null;
        _listaCidades = [];
      }
    });
    try {
      final data = await Supabase.instance.client
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      final cidades =
          (data as List).map((e) => e['municipio'].toString()).toList();

      setState(() {
        _listaCidades = cidades;
        if (manterCidadeAtual && _cidadeSelecionada != null) {
          if (!_listaCidades.contains(_cidadeSelecionada)) {
            _cidadeSelecionada = null;
          }
        }
        _carregandoCidades = false;
      });
    } catch (e) {
      setState(() => _carregandoCidades = false);
      debugPrint('Erro ao buscar cidades: $e');
    }
  }

  Future<void> _salvarDados() async {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor, insira um e-mail válido."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final novoNome = _nomeController.text.toUpperCase();

      Map<String, dynamic> updateData = {
        'usuario_nome': novoNome,
        'email': email,
        'whatsapp': _whatsappController.text,
        'estado': _estadoSelecionado,
        'cidade': _cidadeSelecionada,
      };

      try {
        await Supabase.instance.client
            .from('tab_usuarios')
            .update(updateData)
            .eq('id', user.id);
      } catch (_) {
        updateData.remove('tipo');
        await Supabase.instance.client
            .from('tab_usuarios')
            .update(updateData)
            .eq('id', user.id);
      }

      setState(() {
        _nomeExibicao = novoNome;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dados salvos com sucesso!")),
        );
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a2c42),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFff9800)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a2c42),
      appBar: AppBar(
        title: const Text("Painel do Cliente",
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1a2c42),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFff9800)),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1a2c42),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF253c59)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    "MENU DO CLIENTE",
                    style: TextStyle(
                        color: Color(0xFFff9800),
                        fontSize: 12,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _nomeExibicao.isNotEmpty ? _nomeExibicao : "Carregando...",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.white70),
              title: const Text("Editar Perfil",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF253c59),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFff9800), width: 1),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white12,
                        backgroundImage: _novaImagemArquivo != null
                            ? FileImage(_novaImagemArquivo!) as ImageProvider
                            : (_fotoUrl != null && _fotoUrl!.isNotEmpty
                                ? NetworkImage(_fotoUrl!) as ImageProvider
                                : null),
                        child: (_novaImagemArquivo == null &&
                                (_fotoUrl == null || _fotoUrl!.isEmpty))
                            ? const Icon(Icons.person,
                                size: 50, color: Colors.white54)
                            : null,
                      ),
                      if (_enviandoFoto)
                        const Positioned.fill(
                          child: CircularProgressIndicator(
                              color: Color(0xFFff9800)),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _enviandoFoto ? null : _selecionarEEnviarFoto,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFff9800),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "CONTA CLIENTE",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _nomeExibicao.isNotEmpty ? _nomeExibicao : "Carregando...",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            _buildCard("Meus Dados", [
              _buildEditableField("Nome:", _nomeController,
                  textCapitalization: TextCapitalization.characters),
              _buildEditableField("E-mail:", _emailController),
              _buildEditableField("WhatsApp:", _whatsappController),
              _buildDropdownField(
                label: "Estado:",
                value: _estadoSelecionado,
                items: _listaEstados,
                onChanged: (val) {
                  setState(() {
                    _estadoSelecionado = val;
                    _cidadeSelecionada = null;
                  });
                  if (val != null) _buscarCidades(val);
                },
              ),
              _buildDropdownField(
                label: "Cidade:",
                value: _cidadeSelecionada,
                items: _listaCidades,
                isLoading: _carregandoCidades,
                onChanged: (_carregandoCidades || _listaCidades.isEmpty)
                    ? null
                    : (val) => setState(() => _cidadeSelecionada = val),
              ),
            ]),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvarDados,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFff9800),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text("SALVAR ALTERAÇÕES",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const AcheObraHome()),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text("Sair da Conta",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF253c59),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFFff9800),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller,
      {TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            textCapitalization: textCapitalization,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?)? onChanged,
    bool isLoading = false,
  }) {
    final validValue = items.contains(value) ? value : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          DropdownButtonFormField<String>(
            value: validValue,
            isExpanded: true,
            dropdownColor: const Color(0xFF253c59),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            ),
            hint: isLoading
                ? const Text("Carregando...",
                    style: TextStyle(color: Colors.white54))
                : const Text("Selecione",
                    style: TextStyle(color: Colors.white54)),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
