using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;

namespace ProcesaCompra.Models;

public class Compra
{
    [Key]
    public long Id { get; set; }

    [Required]
    public string Nombre { get; set; } = string.Empty;

    [Required]
    public string Genero { get; set; } = string.Empty; // 'hombre' | 'mujer'

    [Precision(18, 2)] // 🔹 asegura precisión y evita warnings
    public decimal Monto { get; set; }

    [Required]
    public DateTimeOffset Fecha { get; set; }
}