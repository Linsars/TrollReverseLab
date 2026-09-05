// TrollReverseLab/SSHManager/SSHServer.swift
public class SSHServer {
    public static func generateConfig(port: Int) -> String {
        return """
Port \(port)
ListenAddress 127.0.0.1
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
AllowUsers root
PermitEmptyPasswords yes
UsePAM no
MaxAuthTries 3
"""
    }
}
