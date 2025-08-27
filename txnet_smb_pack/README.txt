TX Net+SMB Scripts (simple y fijos)
===============================

Red 192.168.68.x:
  EDGE :  ./net-68-edge.sh   (IP 192.168.68.20/24, GW 192.168.68.1, SMB //192.168.68.128/shared)
  BKEND:  ./net-68-bkend.sh  (IP 192.168.68.21/24, GW 192.168.68.1, SMB //192.168.68.128/shared)
  Solo SMB: ./smb-68.sh

Red 192.168.1.x:
  EDGE :  ./net-1-edge.sh    (IP 192.168.1.20/24,  GW 192.168.1.1,  SMB //192.168.1.67/shared)
  BKEND:  ./net-1-bkend.sh   (IP 192.168.1.21/24,  GW 192.168.1.1,  SMB //192.168.1.67/shared)
  Solo SMB: ./smb-1.sh

Archinstall:
  - ./instedge.sh   (usa /mnt/shared/archinstall/txedgevm/*)
  - ./instbkend.sh  (usa /mnt/shared/archinstall/txbkendvm/*)

Notas:
  * Los scripts escriben credenciales en /etc/cifs-creds/Neural-TXIA_shared.cred (texto plano).
    Esto es inseguro si compartes la ISO. Lo dejas así porque lo solicitaste “fijo y simple”.
  * Requieren que el adaptador se llame algo como en*/eth*; se usa el primero que aparezca.
  * Todos usan DNS 1.1.1.1 y 8.8.8.8.
