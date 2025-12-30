/* HTIF mailboxes for Spike */
SECTIONS
{
  .htif (NOLOAD) :
  {
    . = ALIGN(8);
    tohost = .;
    QUAD(0);
    fromhost = .;
    QUAD(0);
  } > RAM
}
INSERT AFTER .bss;
