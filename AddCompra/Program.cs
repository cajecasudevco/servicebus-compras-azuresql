using AddCompra.Data;
using AddCompra.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapPost("/addcompra", async (CompraRequest req, IConfiguration cfg) =>
{
    if (string.IsNullOrWhiteSpace(req.Nombre) || string.IsNullOrWhiteSpace(req.Genero))
        return Results.BadRequest("Nombre y Genero son obligatorios. Genero: 'hombre' | 'mujer'");

    var genero = req.Genero.Trim().ToLowerInvariant();
    if (genero != "hombre" && genero != "mujer")
        return Results.BadRequest("Genero inválido. Use 'hombre' o 'mujer'.");

    var conn = cfg["ServiceBus:ConnectionString"] 
               ?? Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION_STRING");
    var queue = cfg["ServiceBus:QueueName"] 
               ?? Environment.GetEnvironmentVariable("SERVICE_BUS_QUEUE_NAME") 
               ?? "compras";

    if (string.IsNullOrWhiteSpace(conn))
        return Results.Problem("Falta SERVICEBUS_CONNECTION_STRING");

    var payload = new {
        req.Nombre,
        Genero = genero,
        req.Monto,
        Fecha = DateTimeOffset.UtcNow
    };

    await using var sb = new ServiceBusSenderClient(conn, queue);
    await sb.SendAsync(payload);

    return Results.Ok(new { message = "Compra enviada-Leonisa", payload });
})
.WithName("AddCompra")
.WithOpenApi();

app.Run();
