using Microsoft.EntityFrameworkCore;
using ProcesaCompra.Models;

namespace ProcesaCompra.Data;

public class ComprasDbContext : DbContext
{
    public ComprasDbContext(DbContextOptions<ComprasDbContext> options) : base(options) {}
    public DbSet<Compra> Compras => Set<Compra>();
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Compra>().ToTable("compras");
        base.OnModelCreating(modelBuilder);
    }
}
