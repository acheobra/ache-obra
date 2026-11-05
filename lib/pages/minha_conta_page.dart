import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class MinhaContaPage extends StatefulWidget {
  const MinhaContaPage({super.key});

  @override
  State<MinhaContaPage> createState() => _MinhaContaPageState();
}

class _MinhaContaPageState extends State<MinhaContaPage> {
  bool _carregando = false;
  bool _emEsperaExclusao = false;
  bool _exclusaoConcluida = false;
  int _tempoRestante = 5;
  Timer? _timerExclusao;

  @override
  void dispose() {
    _timerExclusao?.cancel();
    super.dispose();
  }

  Future<void> _confirmarEInativar() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Erro crítico: Nenhum usuário autenticado na sessão!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF253c59),
        title: const Text(
          'Excluir Conta',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'DESEJA REALMENTE EXCLUIR A CONTA E PERDER AS SUAS VANTAGENS?\n\nSeus dados ficarão em espera por 30 dias.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    setState(() {
      _emEsperaExclusao = true;
      _tempoRestante = 5;
    });

    _timerExclusao?.cancel();
    _timerExclusao = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_tempoRestante > 0) {
        setState(() {
          _tempoRestante--;
        });
      }

      if (_tempoRestante == 0) {
        timer.cancel();
        if (_emEsperaExclusao) {
          _executarInativacaoFinal();
        }
      }
    });
  }

  void _cancelarExclusao() {
    _timerExclusao?.cancel();
    setState(() {
      _emEsperaExclusao = false;
      _tempoRestante = 5;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exclusão cancelada com sucesso!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _executarInativacaoFinal() async {
    setState(() {
      _emEsperaExclusao = false;
      _carregando = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) throw "Usuário não autenticado.";

      await supabase.from('tab_usuarios').update({
        'usuario_status': 'inativo',
        'exclusao_solicitada_em': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      setState(() {
        _carregando = false;
        _exclusaoConcluida = true;
      });
    } catch (e) {
      setState(() => _carregando = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao inativar conta: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _finalizarESair() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AcheObraHome()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text(
          'Minha Conta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          _exclusaoConcluida
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF253c59),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF8C00),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFFFF8C00),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'CONTA DESATIVADA COM SUCESSO!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Seus dados ficarão 30 dias em nosso sistema, após esse período serão excluídos permanentemente.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF8C00),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _finalizarESair,
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height -
                          AppBar().preferredSize.height -
                          MediaQuery.of(context).padding.top -
                          48,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gerenciamento de Conta',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Gerencie suas preferências de acesso. A exclusão desativará sua conta permanentemente no sistema.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 30),
                        if (_emEsperaExclusao) ...[
                          Center(
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2C42),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFFF8C00),
                                  width: 1.5,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 75,
                                    height: 75,
                                    child: CircularProgressIndicator(
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              Colors.blue),
                                      backgroundColor: Colors.white12,
                                      strokeWidth: 2.0,
                                      value: _tempoRestante / 5.0,
                                    ),
                                  ),
                                  Text(
                                    '$_tempoRestante',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                        if (_emEsperaExclusao) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF253c59),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.amber,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'AINDA DÁ TEMPO DE CANCELAR ($_tempoRestante)',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                    onPressed: _cancelarExclusao,
                                    child: const Text(
                                      'CANCELAR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Spacer(),
                        if (!_emEsperaExclusao)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.redAccent),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor:
                                    Colors.red.withValues(alpha: 0.1),
                              ),
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.redAccent,
                              ),
                              onPressed: _confirmarEInativar,
                              label: const Text(
                                'EXCLUIR CONTA',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          if (_carregando)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2C42),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF8C00),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        backgroundColor: Colors.white12,
                        strokeWidth: 2.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
