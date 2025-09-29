using Microsoft.EntityFrameworkCore;
using ProcesaCompra;
using ProcesaCompra.Data;

Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        var cfg = ctx.Configuration;
        // Expect full SQL Server connection string via env AZURE_SQL_CONNECTION_STRING
        var sqlConn = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING")
                      ?? cfg.GetConnectionString("AzureSql")
                      ?? throw new InvalidOperationException("Falta AZURE_SQL_CONNECTION_STRING");

        services.AddDbContext<ComprasDbContext>(opt => opt.UseSqlServer(sqlConn));

        // Ensure DB/Tables exist on startup
        services.AddHostedService<Worker>();
        services.AddHostedService(provider => new BootstrapDbHostedService(provider));
    })
    .Build()
    .Run();

public sealed class BootstrapDbHostedService : IHostedService
{
    private readonly IServiceProvider _sp;
    public BootstrapDbHostedService(IServiceProvider sp) => _sp = sp;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ComprasDbContext>();
        await db.Database.EnsureCreatedAsync(cancellationToken);
    }
    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
